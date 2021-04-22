pragma solidity 0.6.12;

import "./BEP20.sol";
import "../Governable.sol";
import "../lib/MinterRole.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

contract Lantti is MinterRole, BEP20, Governable {
  using SafeMath for uint256;

  constructor(address _storage)
        public
        BEP20("LANTTI", "LANTTI")
        Governable(_storage)
    {
      renounceOwnership();

      address gov = governance();
      if (!isMinter(gov)) {
        _addMinter(gov);
      }
    }  

    function mint(address account, uint256 amount) public onlyMinter returns (bool) {
        _mint(account, amount);
        return true;
    }

    function burn(address account, uint256 amount) public onlyMinter {
      _burn(account, amount);
    }
}
