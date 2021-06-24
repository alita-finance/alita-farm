pragma solidity 0.6.12;

// import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/BEP20.sol";
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';
// SyrupBar with Governance.
contract Staking is Ownable{
    address public token; // swap token

    constructor(
        address _token
    ) public {
        token = _token;
    }

    // just in case if not have enough CAKEs.
    function safeTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 cakeBal = IBEP20(token).balanceOf(address(this));
        if (_amount > cakeBal) {
            IBEP20(token).transfer(_to, cakeBal);
        } else {
            IBEP20(token).transfer(_to, _amount);
        }
    }
}
