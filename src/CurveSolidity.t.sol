pragma solidity ^0.6.0;

import "ds-test/test.sol";

import "./CurveSolidity.sol";
import "./CRVLiquidityToken.sol";

////// /nix/store/8xb41r4qd0cjb63wcrxf1qmfg88p0961-dss-6fd7de0/src/dai.sol
// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

/* pragma solidity 0.5.12; */

/* import "./lib.sol"; */

contract DAI {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external auth { wards[guy] = 1; }
    function deny(address guy) external auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Dai/not-authorized");
        _;
    }

    // --- ERC20 Data ---
    string  public constant name     = "Dai Stablecoin";
    string  public constant symbol   = "DAI";
    string  public constant version  = "1";
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint)                      public nonces;

    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;
    // bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)");
    bytes32 public constant PERMIT_TYPEHASH = 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;

    constructor(uint256 chainId_) public {
        wards[msg.sender] = 1;
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            chainId_,
            address(this)
        ));
    }

    // --- Token ---
    function transfer(address dst, uint wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }
    function transferFrom(address src, address dst, uint wad)
        public returns (bool)
    {
        require(balanceOf[src] >= wad, "Dai/insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad, "Dai/insufficient-allowance");
            allowance[src][msg.sender] = sub(allowance[src][msg.sender], wad);
        }
        balanceOf[src] = sub(balanceOf[src], wad);
        balanceOf[dst] = add(balanceOf[dst], wad);
        emit Transfer(src, dst, wad);
        return true;
    }
    function mint(address usr, uint wad) external auth {
        balanceOf[usr] = add(balanceOf[usr], wad);
        totalSupply    = add(totalSupply, wad);
        emit Transfer(address(0), usr, wad);
    }
    function burn(address usr, uint wad) external {
        require(balanceOf[usr] >= wad, "Dai/insufficient-balance");
        if (usr != msg.sender && allowance[usr][msg.sender] != uint(-1)) {
            require(allowance[usr][msg.sender] >= wad, "Dai/insufficient-allowance");
            allowance[usr][msg.sender] = sub(allowance[usr][msg.sender], wad);
        }
        balanceOf[usr] = sub(balanceOf[usr], wad);
        totalSupply    = sub(totalSupply, wad);
        emit Transfer(usr, address(0), wad);
    }
    function approve(address usr, uint wad) external returns (bool) {
        allowance[msg.sender][usr] = wad;
        emit Approval(msg.sender, usr, wad);
        return true;
    }

    // --- Alias ---
    function push(address usr, uint wad) external {
        transferFrom(msg.sender, usr, wad);
    }
    function pull(address usr, uint wad) external {
        transferFrom(usr, msg.sender, wad);
    }
    function move(address src, address dst, uint wad) external {
        transferFrom(src, dst, wad);
    }

    // --- Approve by signature ---
    function permit(address holder, address spender, uint256 nonce, uint256 expiry,
                    bool allowed, uint8 v, bytes32 r, bytes32 s) external
    {
        bytes32 digest =
            keccak256(abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH,
                                     holder,
                                     spender,
                                     nonce,
                                     expiry,
                                     allowed))
        ));

        require(holder != address(0), "Dai/invalid-address-0");
        require(holder == ecrecover(digest, v, r, s), "Dai/invalid-permit");
        require(expiry == 0 || now <= expiry, "Dai/permit-expired");
        require(nonce == nonces[holder]++, "Dai/invalid-nonce");
        uint wad = allowed ? uint(-1) : 0;
        allowance[holder][spender] = wad;
        emit Approval(holder, spender, wad);
    }
}

contract USDC {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);

    string  public  name = "USDC";
    string  public  symbol = "USDC";
    uint256  public  decimals = 6;
    uint256                                            _supply;
    mapping (address => uint256)                       _balances;
    mapping (address => mapping (address => uint256))  _approvals;

    constructor(uint supply) public {
        _balances[msg.sender] = supply;
        _supply = supply;
    }

    function totalSupply() public view returns (uint) {
        return _supply;
    }
    function balanceOf(address src) public view returns (uint) {
        return _balances[src];
    }
    function allowance(address src, address guy) public view returns (uint) {
        return _approvals[src][guy];
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        if (src != msg.sender) {
            require(_approvals[src][msg.sender] >= wad, "insufficient-approval");
            _approvals[src][msg.sender] = sub(_approvals[src][msg.sender], wad);
        }

        require(_balances[src] >= wad, "insufficient-balance");
        _balances[src] = sub(_balances[src], wad);
        _balances[dst] = add(_balances[dst], wad);

        emit Transfer(src, dst, wad);

        return true;
    }

    function approve(address guy, uint wad) public returns (bool) {
        _approvals[msg.sender][guy] = wad;

        emit Approval(msg.sender, guy, wad);

        return true;
    }
}

contract TUSD {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);

    string  public  name = "TrueUSD";
    string  public  symbol = "TUSD";
    uint8   public  decimals = 18;
    address public  implementation;
    uint256                                            _supply;
    mapping (address => uint256)                       _balances;
    mapping (address => mapping (address => uint256))  _approvals;

    constructor(uint supply) public {
        _balances[msg.sender] = supply;
        _supply = supply;
        setImplementation(address(this));
    }

    function setImplementation(address newImplementation) public {
        implementation = newImplementation;
    }

    function totalSupply() public view returns (uint256) {
        return _supply;
    }
    function balanceOf(address src) public view returns (uint256) {
        return _balances[src];
    }
    function allowance(address src, address guy) public view returns (uint256) {
        return _approvals[src][guy];
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad)
        public
        returns (bool)
    {
        if (src != msg.sender) {
            require(_approvals[src][msg.sender] >= wad, "insufficient-approval");
            _approvals[src][msg.sender] = sub(_approvals[src][msg.sender], wad);
        }

        require(_balances[src] >= wad, "insufficient-balance");
        _balances[src] = sub(_balances[src], wad);
        _balances[dst] = add(_balances[dst], wad);

        emit Transfer(src, dst, wad);

        return true;
    }

    function approve(address guy, uint wad) public returns (bool) {
        _approvals[msg.sender][guy] = wad;

        emit Approval(msg.sender, guy, wad);

        return true;
    }
}

contract USDT {
    using SafeMath for uint;

    string  public name = "Tether";
    string  public symbol = "USDT";
    uint    public decimals = 6;
    address public upgradedAddress;
    bool    public deprecated;

    mapping (address => mapping (address => uint)) public allowed;
    mapping (address => uint) public balances;

    uint public constant MAX_UINT = 2**256 - 1;

    address public owner;
    uint public basisPointsRate;
    uint public maximumFee;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);
    event Deprecate(address newAddress);

    modifier onlyPayloadSize(uint size) {
        require(!(msg.data.length < size + 4));
        _;
    }

    constructor(uint _initialSupply) public {
        balances[msg.sender] = _initialSupply;
    }

    function changeFees(uint _basisPointsRate, uint _maximumFee) public {
        basisPointsRate = _basisPointsRate;
        maximumFee = _maximumFee;
    }

    function balanceOf(address _owner) public view returns (uint balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint _value) public onlyPayloadSize(2 * 32) {
        uint fee = (_value.mul(basisPointsRate)).div(10000);
        if (fee > maximumFee) {
            fee = maximumFee;
        }
        uint sendAmount = _value.sub(fee);
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(sendAmount);
        if (fee > 0) {
            balances[owner] = balances[owner].add(fee);
            emit Transfer(msg.sender, owner, fee);
        }
        emit Transfer(msg.sender, _to, sendAmount);
    }

    function transferFrom(address _from, address _to, uint _value) public onlyPayloadSize(3 * 32) {
        uint _allowance = allowed[_from][msg.sender];
        // Check is not needed because sub(_allowance, _value) will already throw if this condition is not met
        // if (_value > _allowance) throw;
        uint fee = (_value.mul(basisPointsRate)).div(10000);
        if (fee > maximumFee) {
            fee = maximumFee;
        }
        if (_allowance < MAX_UINT) {
            allowed[_from][msg.sender] = _allowance.sub(_value);
        }
        uint sendAmount = _value.sub(fee);
        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(sendAmount);
        if (fee > 0) {
            balances[owner] = balances[owner].add(fee);
            emit Transfer(_from, owner, fee);
        }
        emit Transfer(_from, _to, sendAmount);
    }

    function approve(address _spender, uint _value) public onlyPayloadSize(2 * 32) {
        // To change the approve amount you first have to reduce the addresses`
        // allowance to zero by calling `approve(_spender, 0)` if it is not
        // already 0 to mitigate the race condition described here:
        // https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        require(!((_value != 0) && (allowed[msg.sender][_spender] != 0)), "approval failed");
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
    }

    function allowance(address _owner, address _spender) public view returns (uint remaining) {
        return allowed[_owner][_spender];
    }

    function deprecate(address _upgradedAddress) public {
        deprecated = true;
        upgradedAddress = _upgradedAddress;
        emit Deprecate(_upgradedAddress);
    }
}

contract ReentrancyGuard {
    uint256 private _guardCounter;

    constructor () internal {
        _guardCounter = 1;
    }

    modifier nonReentrant() {
        _guardCounter += 1;
        uint256 localCounter = _guardCounter;
        _;
        require(localCounter == _guardCounter, "ReentrancyGuard: reentrant call");
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != accountHash);
    }
    function toPayable(address account) internal pure returns (address payable) {
        return address(uint160(account));
    }
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-call-value
        (bool success, ) = recipient.call.value(amount)("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
}

contract yTOKEN is ERC20, ERC20Detailed {
    using SafeMath for uint256;

    uint256 public pool;
    address public token;

    function safeTransfer(address _token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = _token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address _token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = _token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    constructor (address tokenAddr, uint8 decimals) public ERC20Detailed("iearn", "yToken", decimals) {
        token = tokenAddr;
    }

    // Quick swap low gas method for pool swaps
    function deposit(uint256 _amount)
        external
    {
        require(_amount > 0, "deposit must be greater than 0");
        safeTransferFrom(token, msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares)
        external
    {
        require(_shares > 0, "withdraw must be greater than 0");
        uint256 ibalance = balanceOf(msg.sender);
        require(_shares <= ibalance, "insufficient balance");
        safeTransfer(token, msg.sender, _shares);
        _burn(msg.sender, _shares);
    }

    function getPricePerFullShare() public pure returns (uint) {
        return 1000000000000000000; //placeholder price from yusdt
    } 

}

contract CurveSolidityTest is DSTest {
    DAI dai;
    yTOKEN ydai;
    USDC usdc;
    yTOKEN yusdc;
    TUSD tusd;
    yTOKEN ytusd;
    USDT usdt;
    yTOKEN yusdt;

    CRVLiquidityToken crv;

    CurveSolidity exchange;

    // 1,000 tokens per
    function setUp() public {
        dai = new DAI(1);
        dai.mint(address(this), 1000000000000000000000);
        ydai = new yTOKEN(address(dai), 18);
        dai.approve(address(ydai), uint(-1));

        usdc = new USDC(1000000000);
        yusdc = new yTOKEN(address(usdc), 6);
        usdc.approve(address(yusdc), uint(-1));

        tusd = new TUSD(1000000000000000000000);
        ytusd = new yTOKEN(address(tusd), 18);
        tusd.approve(address(ytusd), uint(-1));

        usdt = new USDT(1000000000);
        yusdt = new yTOKEN(address(usdt), 6);
        usdt.approve(address(yusdt), uint(-1));

        crv = new CRVLiquidityToken();

        address[4] memory underlying_coins = [address(dai), address(usdc), address(usdt), address(tusd)];
        address[4] memory coins = [address(ydai), address(yusdc), address(yusdt), address(ytusd)];
        exchange = new CurveSolidity(coins, underlying_coins, address(crv));

        crv.setOwner(address(exchange));
    }

    function test_add_liq() public {
        ydai.deposit(10000000000000000000);
        ydai.approve(address(exchange), uint(-1));

        yusdc.deposit(10000000);
        yusdc.approve(address(exchange), uint(-1));

        yusdt.deposit(10000000);
        yusdt.approve(address(exchange), uint(-1));

        ytusd.deposit(10000000000000000000);
        ytusd.approve(address(exchange), uint(-1));

        uint256[4] memory coins;
        coins[0] = 10000000000000000000;
        coins[1] = 10000000;
        coins[2] = 10000000;
        coins[3] = 10000000000000000000;
        exchange.add_liquidity(coins, 0);
        assertEq(crv.balanceOf(address(this)), 40000000000000000000);
    }

    // // --- Unequal Decimals ---
    // function test_swap_underlying_dai_usdc() public {
    //     dai.approve(address(exchange), uint(-1));
    //     ydai.deposit(11000000000000000000);
    //     ydai.approve(address(exchange), uint(-1));

    //     yusdc.deposit(10000000);
    //     yusdc.approve(address(exchange), uint(-1));

    //     yusdt.deposit(10000000);
    //     yusdt.approve(address(exchange), uint(-1));

    //     ytusd.deposit(10000000000000000000);
    //     ytusd.approve(address(exchange), uint(-1));

    //     uint256[4] memory coins;
    //     coins[0] = 10000000000000000000;
    //     coins[1] = 10000000;
    //     coins[2] = 10000000;
    //     coins[3] = 10000000000000000000;
    //     exchange.add_liquidity(coins, 0);
    //     assertEq(crv.balanceOf(address(this)), 40000000000000000000);

    //     exchange.exchange_underlying(0,1,1000000000000000000,950000);
    //     assertTrue(usdc.balanceOf(address(this)) >= (1000000000 - 10000000 + 950000));
    // }

    // function test_swap_underlying_usdc_dai() public {
    //     ydai.deposit(10000000000000000000);
    //     ydai.approve(address(exchange), uint(-1));

    //     usdc.approve(address(exchange), uint(-1));
    //     yusdc.deposit(11000000);
    //     yusdc.approve(address(exchange), uint(-1));

    //     yusdt.deposit(10000000);
    //     yusdt.approve(address(exchange), uint(-1));

    //     ytusd.deposit(10000000000000000000);
    //     ytusd.approve(address(exchange), uint(-1));

    //     uint256[4] memory coins;
    //     coins[0] = 10000000000000000000;
    //     coins[1] = 10000000;
    //     coins[2] = 10000000;
    //     coins[3] = 10000000000000000000;
    //     exchange.add_liquidity(coins, 0);
    //     assertEq(crv.balanceOf(address(this)), 40000000000000000000);

    //     exchange.exchange_underlying(1,0,1000000,950000000000000000);
    //     assertTrue(dai.balanceOf(address(this)) >= (1000000000000000000000 - 10000000000000000000 + 950000000000000000));
    // }

    // function test_swap_underlying_usdc_tusd() public {
    //     ydai.deposit(10000000000000000000);
    //     ydai.approve(address(exchange), uint(-1));

    //     usdc.approve(address(exchange), uint(-1));
    //     yusdc.deposit(11000000);
    //     yusdc.approve(address(exchange), uint(-1));

    //     usdt.approve(address(exchange), uint(-1));
    //     yusdt.deposit(11000000);
    //     yusdt.approve(address(exchange), uint(-1));

    //     ytusd.deposit(10000000000000000000);
    //     ytusd.approve(address(exchange), uint(-1));

    //     uint256[4] memory coins;
    //     coins[0] = 10000000000000000000;
    //     coins[1] = 10000000;
    //     coins[2] = 10000000;
    //     coins[3] = 10000000000000000000;
    //     exchange.add_liquidity(coins, 0);
    //     assertEq(crv.balanceOf(address(this)), 40000000000000000000);

    //     exchange.exchange_underlying(1,3,1000000,950000000000000000);
    //     assertTrue(tusd.balanceOf(address(this)) >= (1000000000000000000000 - 10000000000000000000 + 950000000000000000));
    // }

    // // --- Equal Decimals ---
    // function test_swap_underlying_dai_tusd() public {
    //     dai.approve(address(exchange), uint(-1));
    //     ydai.deposit(11000000000000000000);
    //     ydai.approve(address(exchange), uint(-1));

    //     usdc.approve(address(exchange), uint(-1));
    //     yusdc.deposit(10000000);
    //     yusdc.approve(address(exchange), uint(-1));

    //     usdt.approve(address(exchange), uint(-1));
    //     yusdt.deposit(10000000);
    //     yusdt.approve(address(exchange), uint(-1));

    //     ytusd.deposit(10000000000000000000);
    //     ytusd.approve(address(exchange), uint(-1));

    //     uint256[4] memory coins;
    //     coins[0] = 10000000000000000000;
    //     coins[1] = 10000000;
    //     coins[2] = 10000000;
    //     coins[3] = 10000000000000000000;
    //     exchange.add_liquidity(coins, 0);
    //     assertEq(crv.balanceOf(address(this)), 40000000000000000000);

    //     exchange.exchange_underlying(0,3,1000000000000000000,950000000000000000);
    //     assertTrue(tusd.balanceOf(address(this)) >= (1000000000000000000000 - 10000000000000000000 + 950000000000000000));
    // }

    function test_swap_underlying_usdt_usdc() public {
        dai.approve(address(exchange), uint(-1));
        ydai.deposit(10000000000000000000);
        ydai.approve(address(exchange), uint(-1));

        usdc.approve(address(exchange), uint(-1));
        yusdc.deposit(10000000);
        yusdc.approve(address(exchange), uint(-1));

        usdt.approve(address(exchange), uint(-1));
        yusdt.deposit(11000000);
        yusdt.approve(address(exchange), uint(-1));

        ytusd.deposit(10000000000000000000);
        ytusd.approve(address(exchange), uint(-1));

        uint256[4] memory coins;
        coins[0] = 10000000000000000000;
        coins[1] = 10000000;
        coins[2] = 10000000;
        coins[3] = 10000000000000000000;
        exchange.add_liquidity(coins, 0);
        assertEq(crv.balanceOf(address(this)), 40000000000000000000);

        exchange.exchange_underlying(2,1,1000000,950000);
        assertTrue(usdc.balanceOf(address(this)) >= (1000000000 - 10000000 + 950000));
    }

    // --- Unequal Decimals ---
    function test_swap_dai_usdc() public {
        ydai.deposit(11000000000000000000);
        ydai.approve(address(exchange), uint(-1));

        yusdc.deposit(10000000);
        yusdc.approve(address(exchange), uint(-1));

        yusdt.deposit(10000000);
        yusdt.approve(address(exchange), uint(-1));

        ytusd.deposit(10000000000000000000);
        ytusd.approve(address(exchange), uint(-1));

        uint256[4] memory coins;
        coins[0] = 10000000000000000000;
        coins[1] = 10000000;
        coins[2] = 10000000;
        coins[3] = 10000000000000000000;
        exchange.add_liquidity(coins, 0);
        assertEq(crv.balanceOf(address(this)), 40000000000000000000);

        exchange.exchange(0,1,1000000000000000000,950000);
        assertTrue(yusdc.balanceOf(address(this)) >= 950000);
    }

    function test_swap_usdc_dai() public {
        ydai.deposit(10000000000000000000);
        ydai.approve(address(exchange), uint(-1));

        usdc.approve(address(exchange), uint(-1));
        yusdc.deposit(11000000);
        yusdc.approve(address(exchange), uint(-1));

        yusdt.deposit(10000000);
        yusdt.approve(address(exchange), uint(-1));

        ytusd.deposit(10000000000000000000);
        ytusd.approve(address(exchange), uint(-1));

        uint256[4] memory coins;
        coins[0] = 10000000000000000000;
        coins[1] = 10000000;
        coins[2] = 10000000;
        coins[3] = 10000000000000000000;
        exchange.add_liquidity(coins, 0);
        assertEq(crv.balanceOf(address(this)), 40000000000000000000);

        exchange.exchange(1,0,1000000,950000000000000000);
        assertTrue(ydai.balanceOf(address(this)) >= 950000000000000000);
    }

    function test_swap_usdt_tusd() public {
        ydai.deposit(10000000000000000000);
        ydai.approve(address(exchange), uint(-1));

        usdc.approve(address(exchange), uint(-1));
        yusdc.deposit(10000000);
        yusdc.approve(address(exchange), uint(-1));

        usdt.approve(address(exchange), uint(-1));
        yusdt.deposit(11000000);
        yusdt.approve(address(exchange), uint(-1));

        ytusd.deposit(10000000000000000000);
        ytusd.approve(address(exchange), uint(-1));

        uint256[4] memory coins;
        coins[0] = 10000000000000000000;
        coins[1] = 10000000;
        coins[2] = 10000000;
        coins[3] = 10000000000000000000;
        exchange.add_liquidity(coins, 0);
        assertEq(crv.balanceOf(address(this)), 40000000000000000000);

        exchange.exchange(2,3,1000000,950000000000000000);
        assertTrue(ytusd.balanceOf(address(this)) >= 950000000000000000);
    }

    // --- Equal Decimals ---
    function test_swap_dai_tusd() public {
        dai.approve(address(exchange), uint(-1));
        ydai.deposit(11000000000000000000);
        ydai.approve(address(exchange), uint(-1));

        usdc.approve(address(exchange), uint(-1));
        yusdc.deposit(10000000);
        yusdc.approve(address(exchange), uint(-1));

        usdt.approve(address(exchange), uint(-1));
        yusdt.deposit(10000000);
        yusdt.approve(address(exchange), uint(-1));

        ytusd.deposit(10000000000000000000);
        ytusd.approve(address(exchange), uint(-1));

        uint256[4] memory coins;
        coins[0] = 10000000000000000000;
        coins[1] = 10000000;
        coins[2] = 10000000;
        coins[3] = 10000000000000000000;
        exchange.add_liquidity(coins, 0);
        assertEq(crv.balanceOf(address(this)), 40000000000000000000);

        exchange.exchange(0,3,1000000000000000000,950000000000000000);
        assertTrue(ytusd.balanceOf(address(this)) >= 950000000000000000);
    }

    function test_swap_usdt_usdc() public {
        dai.approve(address(exchange), uint(-1));
        ydai.deposit(10000000000000000000);
        ydai.approve(address(exchange), uint(-1));

        usdc.approve(address(exchange), uint(-1));
        yusdc.deposit(10000000);
        yusdc.approve(address(exchange), uint(-1));

        usdt.approve(address(exchange), uint(-1));
        yusdt.deposit(11000000);
        yusdt.approve(address(exchange), uint(-1));

        ytusd.deposit(10000000000000000000);
        ytusd.approve(address(exchange), uint(-1));

        uint256[4] memory coins;
        coins[0] = 10000000000000000000;
        coins[1] = 10000000;
        coins[2] = 10000000;
        coins[3] = 10000000000000000000;
        exchange.add_liquidity(coins, 0);
        assertEq(crv.balanceOf(address(this)), 40000000000000000000);

        exchange.exchange(2,1,1000000,950000);
        assertTrue(yusdc.balanceOf(address(this)) >= 950000);
    }

    // function test_remove_liquidity() public {
    //     dai.approve(address(exchange), uint(-1));
    //     ydai.deposit(11000000000000000000);
    //     ydai.approve(address(exchange), uint(-1));

    //     usdc.approve(address(exchange), uint(-1));
    //     yusdc.deposit(10000000);
    //     yusdc.approve(address(exchange), uint(-1));

    //     usdt.approve(address(exchange), uint(-1));
    //     yusdt.deposit(10000000);
    //     yusdt.approve(address(exchange), uint(-1));

    //     ytusd.deposit(10000000000000000000);
    //     ytusd.approve(address(exchange), uint(-1));

    //     uint256[4] memory coins;
    //     coins[0] = 10000000000000000000;
    //     coins[1] = 10000000;
    //     coins[2] = 10000000;
    //     coins[3] = 10000000000000000000;
    //     exchange.add_liquidity(coins, 0);
    //     assertEq(crv.balanceOf(address(this)), 400000000000000000000);

    //     exchange.exchange(0,3,100000000000000000,95000000000000000);
    //     assertTrue(ytusd.balanceOf(address(this)) >= 95000000000000000);

    //     crv.approve(address(exchange), uint(-1));

    //     uint256[4] memory min_amt;
    //     min_amt[0] = 100000000000000000;
    //     min_amt[1] = 100000;
    //     min_amt[2] = 100000;
    //     min_amt[3] = 100000000000000000;
    //     exchange.remove_liquidity(10000000000000000000, min_amt);
    //     assertEq(min_amt[2], 0);
    // }

    // function test_remove_liquidity_imbalanced() public {
    //     dai.approve(address(exchange), uint(-1));
    //     ydai.deposit(11000000000000000000);
    //     ydai.approve(address(exchange), uint(-1));

    //     usdc.approve(address(exchange), uint(-1));
    //     yusdc.deposit(10000000);
    //     yusdc.approve(address(exchange), uint(-1));

    //     usdt.approve(address(exchange), uint(-1));
    //     yusdt.deposit(10000000);
    //     yusdt.approve(address(exchange), uint(-1));

    //     ytusd.deposit(10000000000000000000);
    //     ytusd.approve(address(exchange), uint(-1));

    //     uint256[4] memory coins;
    //     coins[0] = 10000000000000000000;
    //     coins[1] = 10000000;
    //     coins[2] = 10000000;
    //     coins[3] = 10000000000000000000;
    //     exchange.add_liquidity(coins, 0);
    //     assertEq(crv.balanceOf(address(this)), 41117185864399595560);

    //     crv.approve(address(exchange), uint(-1));

    //     uint256[4] memory amounts;
    //     coins[0] = 10;
    //     coins[1] = 0;
    //     coins[2] = 0;
    //     coins[3] = 0;

    //     uint256 D2 = exchange.remove_liquidity_imbalance(amounts, 1000000000000000000);
    //     assertEq(D2, 0);
    // }
}
