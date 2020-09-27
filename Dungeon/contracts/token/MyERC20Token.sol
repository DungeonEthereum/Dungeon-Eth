pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyERC20Token is ERC20, Ownable {

    address public minter;
    address public burner;

    constructor (string memory name, string memory symbol, address _minter, address _burner) public ERC20(name, symbol) {
        minter = _minter;
        burner = _burner;
    }

    function setBurner(address _newBurner) external onlyOwner {
        burner = _newBurner;
    }

    function mint(address _to, uint256 _amount) public {
        require(msg.sender == minter, "Only minter can mint this token");
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) public {
        require(msg.sender == burner, "Only burner can burn this token");
        _burn(msg.sender, _amount);
    }

}
