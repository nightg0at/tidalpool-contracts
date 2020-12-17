/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000
          }
        }
      },
      {
        version: "0.6.6" // uniswap safemath
      },
      {
        version: "0.5.16" // harvest farm (restaking) 
      }
    ]
  }
}