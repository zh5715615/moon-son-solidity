const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const projectRoot = path.resolve(__dirname, "..");
const codegenPom = path.join(__dirname, "web3j-codegen-pom.xml");

function fail(message) {
  throw new Error(message);
}

function readArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--")) fail(`Unknown argument: ${argument}`);
    const key = argument.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail(`Missing value for --${key}`);
    options[key] = value;
    index += 1;
  }
  return options;
}

function resolveCommand(command) {
  return process.platform === "win32" && command === "mvn" ? "mvn.cmd" : command;
}

function buildClasspath(workRoot) {
  fs.mkdirSync(workRoot, { recursive: true });
  const classpathFile = path.join(workRoot, "codegen-classpath.txt");
  const candidates = [process.env.MAVEN_CMD, "mvn"].filter(Boolean);

  for (const candidate of [...new Set(candidates)]) {
    fs.rmSync(classpathFile, { force: true });
    const result = spawnSync(
      resolveCommand(candidate),
      [
        "-q",
        "-f", codegenPom,
        "dependency:build-classpath",
        `-Dmdep.outputFile=${classpathFile}`,
      ],
      { cwd: projectRoot, stdio: "inherit", shell: process.platform === "win32" }
    );
    if (!result.error && result.status === 0 && fs.existsSync(classpathFile)) {
      const classpath = fs.readFileSync(classpathFile, "utf8").trim();
      if (classpath) return classpath;
    }
  }

  fail("Unable to build the Web3j generator classpath. Install Maven or set MAVEN_CMD.");
}

function validateFile(filePath, label) {
  if (!fs.existsSync(filePath)) fail(`${label} not found: ${filePath}`);
  if (!fs.statSync(filePath).isFile()) fail(`${label} is not a file: ${filePath}`);
  if (!fs.readFileSync(filePath, "utf8").trim()) fail(`${label} is empty: ${filePath}`);
}

function resolveContractName(abiPath, explicitName) {
  const abiBaseName = path.basename(abiPath, path.extname(abiPath));
  const inferredName = abiBaseName.includes("_sol_")
    ? abiBaseName.slice(abiBaseName.lastIndexOf("_sol_") + 5)
    : abiBaseName;
  const contractName = explicitName || inferredName;
  if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(contractName)) {
    fail(`Invalid Java class name: ${contractName}. Pass a valid name with --name.`);
  }
  return contractName;
}

function main() {
  const options = readArguments(process.argv.slice(2));
  if (!options.abi || !options.bin) {
    fail("Usage: npm run generate:java:abi-bin -- --abi <file.abi> --bin <file.bin> [--name <class>] [--package <java.package>] [--output <directory>]");
  }

  const abiPath = path.resolve(options.abi);
  const binPath = path.resolve(options.bin);
  const contractName = resolveContractName(abiPath, options.name);
  const packageName = options.package || "tcbv.zhaohui.moon.contract";
  const outputRoot = path.resolve(options.output || path.join(projectRoot, "build", "web3j-codegen", "custom-output"));
  const workRoot = path.join(projectRoot, "build", "web3j-codegen", "custom");
  const inputRoot = path.join(workRoot, "input");

  validateFile(abiPath, "ABI");
  validateFile(binPath, "BIN");
  fs.mkdirSync(outputRoot, { recursive: true });
  fs.mkdirSync(inputRoot, { recursive: true });

  const normalizedAbiPath = path.join(inputRoot, `${contractName}.abi`);
  const normalizedBinPath = path.join(inputRoot, `${contractName}.bin`);
  fs.copyFileSync(abiPath, normalizedAbiPath);
  fs.copyFileSync(binPath, normalizedBinPath);

  const classpath = buildClasspath(workRoot);
  const java = process.env.JAVA_HOME
    ? path.join(process.env.JAVA_HOME, "bin", process.platform === "win32" ? "java.exe" : "java")
    : "java";
  const result = spawnSync(
    java,
    [
      "-cp", classpath,
      "org.web3j.codegen.SolidityFunctionWrapperGenerator",
      "--javaTypes",
      "-a", normalizedAbiPath,
      "-b", normalizedBinPath,
      "-o", outputRoot,
      "-p", packageName,
    ],
    { cwd: projectRoot, stdio: "inherit" }
  );

  if (result.error) fail(`Unable to start Web3j generator: ${result.error.message}`);
  if (result.status !== 0) fail(`Web3j generation failed with exit code ${result.status}`);

  console.log(`Generated ${path.join(outputRoot, ...packageName.split("."), `${contractName}.java`)}`);
}

try {
  main();
} catch (error) {
  console.error(error.message || error);
  process.exitCode = 1;
}
