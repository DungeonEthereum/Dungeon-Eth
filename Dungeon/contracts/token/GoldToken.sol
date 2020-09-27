pragma solidity >=0.5.0;

import "./MyERC20Token.sol";

contract GoldToken is MyERC20Token {
    constructor (address _minter, address _burner) public MyERC20Token("Dungeon Gold", "GOLD", _minter, _burner) {}
}
