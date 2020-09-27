pragma solidity >=0.5.0;

import "./MyERC20Token.sol";

contract ShieldToken is MyERC20Token {
    constructor (address _minter, address _burner) public MyERC20Token("Dungeon Shield", "SHLD", _minter, _burner) {}
}
