async function expectRevert(promise) {
  try {
    await promise;
    assert.fail("Expected transaction to revert");
  } catch (error) {
    assert(
      error.message.includes("revert") || error.message.includes("invalid opcode"),
      `Expected EVM revert, got: ${error.message}`
    );
  }
}

module.exports = { expectRevert };
