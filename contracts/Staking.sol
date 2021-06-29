pragma solidity 0.6.12;

// import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';
// SyrupBar with Governance.
contract Staking is Ownable{
    address public alita; // swap token

    constructor(
        address _alita
    ) public {
        alita = _alita;
    }

    // just in case if not have enough CAKEs.
    function safeTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 aliBal = IBEP20(alita).balanceOf(address(this));
        if (_amount > aliBal) {
            IBEP20(alita).transfer(_to, aliBal);
        } else {
            IBEP20(alita).transfer(_to, _amount);
        }
    }
}
