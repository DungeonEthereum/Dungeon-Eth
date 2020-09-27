pragma solidity >=0.5.0;

import "./MyERC20Token.sol";

contract WoodToken is MyERC20Token {
    constructor (address _minter, address _burner) public MyERC20Token("Dungeon Wood", "WOOD", _minter, _burner) {}
}
