pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./MyERC20Token.sol";

contract MockERC20 is MyERC20Token {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply,
        address burner
    ) public MyERC20Token(name, symbol, msg.sender, burner) {
        _mint(msg.sender, supply);
    }
}