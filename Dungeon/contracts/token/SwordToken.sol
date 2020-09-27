pragma solidity >=0.5.0;

import "./MyERC20Token.sol";

contract SwordToken is MyERC20Token {
    constructor (address _minter, address _burner) public MyERC20Token("Dungeon Sword", "SWRD", _minter, _burner) {}
}
