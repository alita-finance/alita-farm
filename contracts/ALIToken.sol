pragma solidity >=0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

interface AliToken is IBEP20 {

    function getKeepPercent() external view returns(uint);

    function getInitialRewardPerBlock() external view returns(uint);

    function getMaxiumPeriodIndex() external view returns(uint);

    function getBlockPerPeriod() external view returns(uint);

    function mint(address _to, uint256 _amount) external;

}