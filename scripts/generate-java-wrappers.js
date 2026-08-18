const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const projectRoot = path.resolve(__dirname, "..");
const backendRoot = process.env.MOON_SON_SVC_DIR
  ? path.resolve(process.env.MOON_SON_SVC_DIR)
  : path.resolve(projectRoot, "..", "moon-son-svc");
const javaSourceRoot = path.join(backendRoot, "src", "main", "java");
const packageName = "tcbv.zhaohui.moon.contract";
const packagePath = packageName.split(".").join(path.sep);
const artifactRoot = path.join(projectRoot, "build", "contracts");
const workRoot = path.join(projectRoot, "build", "web3j-codegen");
const inputRoot = path.join(workRoot, "input");
const outputRoot = path.join(workRoot, "output");
const codegenPom = path.join(projectRoot, "scripts", "web3j-codegen-pom.xml");
const contracts = ["YION", "GameRewardPool", "Bullfigthing", "GoldenFlower", "Landlords"];

function fail(message) {
  throw new Error(message);
}

function resolveMavenCommands() {
  const windowsWrapper = path.join(backendRoot, "mvnw.cmd");
  const unixWrapper = path.join(backendRoot, "mvnw");
  const commands = [];
  if (process.env.MAVEN_CMD) commands.push(process.env.MAVEN_CMD);
  commands.push(process.platform === "win32" ? "mvn.cmd" : "mvn");
  if (process.platform === "win32" && fs.existsSync(windowsWrapper)) commands.push(windowsWrapper);
  if (fs.existsSync(unixWrapper)) commands.push(unixWrapper);
  return [...new Set(commands)];
}

if (!fs.existsSync(path.join(backendRoot, "pom.xml"))) {
  fail(`Java backend not found: ${backendRoot}. Set MOON_SON_SVC_DIR if it is elsewhere.`);
}
if (!fs.existsSync(artifactRoot)) {
  fail(`Truffle artifacts not found: ${artifactRoot}. Run npm run compile first.`);
}

fs.rmSync(workRoot, { recursive: true, force: true });
fs.mkdirSync(inputRoot, { recursive: true });
fs.mkdirSync(outputRoot, { recursive: true });

for (const contractName of contracts) {
  const artifactPath = path.join(artifactRoot, `${contractName}.json`);
  if (!fs.existsSync(artifactPath)) fail(`Missing artifact: ${artifactPath}`);
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  if (!Array.isArray(artifact.abi)) fail(`Artifact ABI is invalid: ${artifactPath}`);
  if (!artifact.bytecode || artifact.bytecode === "0x") fail(`Artifact bytecode is empty: ${artifactPath}`);

  fs.writeFileSync(path.join(inputRoot, `${contractName}.abi`), JSON.stringify(artifact.abi));
  fs.writeFileSync(
    path.join(inputRoot, `${contractName}.bin`),
    artifact.bytecode.replace(/^0x/, "")
  );
}

const classpathFile = path.join(workRoot, "codegen-classpath.txt");
let classpathResolved = false;
for (const maven of resolveMavenCommands()) {
  fs.rmSync(classpathFile, { force: true });
  const classpathResult = spawnSync(
    maven,
    [
      "-q",
      "-f", codegenPom,
      "dependency:build-classpath",
      `-Dmdep.outputFile=${classpathFile}`,
    ],
    { cwd: backendRoot, stdio: "inherit", shell: process.platform === "win32" }
  );
  if (!classpathResult.error && classpathResult.status === 0 && fs.existsSync(classpathFile)) {
    classpathResolved = true;
    break;
  }
}
if (!classpathResolved) {
  fail("Unable to build the Web3j generator classpath");
}
const codegenClasspath = fs.readFileSync(classpathFile, "utf8").trim();
if (!codegenClasspath) fail("Web3j generator classpath is empty");
const javaHome = process.env.JAVA_HOME;
const java = javaHome
  ? path.join(javaHome, "bin", process.platform === "win32" ? "java.exe" : "java")
  : "java";

for (const contractName of contracts) {
  console.log(`Generating ${contractName}.java`);
  const generatorArgs = [
    "--javaTypes",
    "-a", path.join(inputRoot, `${contractName}.abi`),
    "-b", path.join(inputRoot, `${contractName}.bin`),
    "-o", outputRoot,
    "-p", packageName,
  ];
  const result = spawnSync(
    java,
    [
      "-cp", codegenClasspath,
      "org.web3j.codegen.SolidityFunctionWrapperGenerator",
      ...generatorArgs,
    ],
    { cwd: backendRoot, stdio: "inherit" }
  );
  if (result.error) fail(`Unable to start Web3j generator: ${result.error.message}`);
  if (result.status !== 0) fail(`Web3j generation failed for ${contractName}`);
}

const generatedPackageRoot = path.join(outputRoot, packagePath);
const targetPackageRoot = path.join(javaSourceRoot, packagePath);
fs.mkdirSync(targetPackageRoot, { recursive: true });

for (const contractName of contracts) {
  const generatedFile = path.join(generatedPackageRoot, `${contractName}.java`);
  const targetFile = path.join(targetPackageRoot, `${contractName}.java`);
  if (!fs.existsSync(generatedFile)) fail(`Expected generated wrapper was not created: ${generatedFile}`);
  const generatedSource = fs.readFileSync(generatedFile, "utf8");
  const normalizedSource = generatedSource.replace(/[ \t]+$/gm, "");
  fs.writeFileSync(targetFile, normalizedSource);
  console.log(`Updated ${targetFile}`);
}

console.log(`Generated ${contracts.length} Java wrappers with Web3j 5.0.0.`);
