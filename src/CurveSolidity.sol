pragma solidity ^0.6.0;

interface mERC20 {
    function totalSupply() external view returns(uint256);
    function allowance(address, address) external view returns(uint256);
    function transfer(address, uint256) external returns(bool);
    function transferFrom(address, address, uint256) external returns(bool);
    function approve(address, uint256) external returns(bool);
    function mint(address, uint256) external;
    function burn(uint256) external;
    function burnFrom(address, uint256) external;
    function name() external view returns(string memory);
    function symbol() external view returns(string memory);
    function decimals() external view returns(uint256);
    function balanceOf(address) external returns(uint256);
    function set_minter(address) external;
}

interface yERC20 {
    function totalSupply() external view returns(uint256);
    function allowance(address, address) external view returns(uint256);
    function transfer(address, uint256) external returns(bool);
    function transferFrom(address, address, uint256) external returns(bool);
    function approve(address, uint256) external returns(bool);
    function name() external view returns(string memory);
    function symbol() external view returns(string memory);
    function decimals() external view returns(uint256);
    function balanceOf(address) external returns(uint256);
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function getPricePerFullShare() external view returns(uint256);
}

contract CurveSolidity {
    uint256 constant ZEROS256 = 0;
    uint256[4] ZEROS = [ZEROS256, ZEROS256, ZEROS256, ZEROS256];
    uint256 constant FEE_DENOMINATOR = 10 ** 10;
    uint256 constant PRECISION = 10 ** 18;
    uint256[4] PRECISION_MUL = [1, 1000000000000, 1000000000000, 1];
    //PRECISION_MUL: constant(uint256[4]) = [
    //PRECISION / convert(10 ** 18, uint256),  DAI
    //PRECISION / convert(10 ** 6, uint256),   USDC
    //PRECISION / convert(10 ** 6, uint256),   USDT
    //PRECISION / convert(10 ** 18, uint256)]  TUSD
    uint256 constant admin_actions_delay = 3 * 86400;

    // --- EVENTS ---
    event TokenExchange(address indexed buyer, uint256 sold_id, uint256 tokens_sold, uint256 bought_id, uint256 tokens_bought);
    event TokenExchangeUnderlying(address indexed buyer, uint256 sold_id, uint256 tokens_sold, uint256 bought_id, uint256 tokens_bought);
    event AddLiquidity(address indexed provider, uint256[4] token_amounts, uint256[4] fees, uint256 invariant, uint256 token_supply);
    event RemoveLiquidity(address indexed provider, uint256[4] token_amounts, uint256[4] fees, uint256 token_supply);
    event RemoveLiquidityImbalance(address indexed provider, uint256[4] token_amounts, uint256[4] fees, uint256 invariant, uint256 token_supply);
    event CommitNewAdmin(uint256 deadline, address indexed admin);
    event NewAdmin(address indexed admin);
    event CommitNewParameters(uint256 deadline, uint256 A, uint256 fee, uint256 admin_fee);
    event NewParameters(uint256 A, uint256 fee, uint256 admin_fee);

    // --- PUBLIC VARIABLES ---
    address[4] public coins;
    address[4] public underlying_coins;
    uint256[4] public balances;
    uint256 public A;
    uint256 public fee;
    uint256 public admin_fee;
    uint256 public constant max_admin_fee = 5 * 10 ** 9;
    address public owner;
    mERC20 liquidity_token;
    uint256 public admin_actions_deadline;
    uint256 public transfer_ownership_deadline;
    uint256 public future_A;
    uint256 public future_fee;
    uint256 public future_admin_fee;
    address public future_owner;
    uint256 kill_deadline;
    uint256 constant kill_deadline_qt = 2 * 30 * 86400;
    bool is_killed;

    // --- MODIFIERS ---
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // --- HELPERS ---
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    constructor(address[4] memory _coins, address[4] memory _underlying_coins, address _pool_token) public {
        for(uint256 i = 0; i < 4; i++) {
            require(_coins[i] != address(0), "can't be 0");
            require(_underlying_coins[i] != address(0), "can't be 0");
            balances[i] = 0;
        }
        coins = _coins;
        underlying_coins = _underlying_coins;
        A = 2000;
        fee = 4000000;
        admin_fee = 0;
        owner = msg.sender;
        kill_deadline = block.timestamp + kill_deadline_qt;
        is_killed = false;
        liquidity_token = mERC20(_pool_token);
    }

    function _stored_rates() internal view returns(uint256[4] memory) {
        uint256[4] memory result = PRECISION_MUL;
        for(uint256 i = 0; i < 4; i++) {
            result[i] = result[i] * yERC20(coins[i]).getPricePerFullShare();
        }
        return result;
    }

    function _xp(uint256[4] memory rates) internal view returns(uint256[4] memory) {
        uint256[4] memory result = rates;
        for(uint256 i = 0; i < 4; i++) {
            result[i] = result[i] * balances[i] / PRECISION;
        }
        return result;
    }

    function _xp_mem(uint256[4] memory rates, uint256[4] memory _balances) internal pure returns(uint256[4] memory) {
        uint256[4] memory result = rates;
        for(uint256 i = 0; i < 4; i++) {
            result[i] = result[i] * _balances[i] / PRECISION;
        }
        return result;
    }

    function get_D(uint256[4] memory xp) internal view returns(uint256) {
        uint256 S = 0;
        for(uint256 i = 0; i < 4; i++) {
            S += xp[i];
        }
        if (S == 0) {
            return 0;
        }

        uint256 Dprev = 0;
        uint256 D = S;
        uint256 Ann = A * 4;
        for(uint256 i = 0; i < 255; i++) {
            uint256 D_P = D;
            for(uint256 ii = 0; ii < 4; ii++) {
                D_P = D_P * D / (xp[ii] * 4 + 1);
            }
            Dprev = D;
            D = (Ann * S + D_P * 4) * D / ((Ann - 1) * D + 5 * D_P);
            if (D > Dprev) {
                if (D - Dprev <= 1) {
                    break;
                }
            } else {
                if (Dprev - D <= 1) {
                    break;
                }
            }
        }

        return D;
    }

    function get_D_mem(uint256[4] memory rates, uint256[4] memory _balances) internal view returns(uint256) {
        return get_D(_xp_mem(rates, _balances));
    }

    function get_virtual_price() public view returns(uint256) {
        uint256 D = get_D(_xp(_stored_rates()));
        return D * PRECISION / liquidity_token.totalSupply();
    }

    function calc_token_amount(uint256[4] memory amounts, bool deposit) public view returns(uint256) {
        uint256[4] memory _balances = balances;
        uint256[4] memory rates = _stored_rates();
        uint256 D0 = get_D_mem(rates, _balances);
        for(uint256 i = 0; i < 4; i++) {
            if (deposit) {
                _balances[i] += amounts[i];
            } else {
                _balances[i] -= amounts[i];
            }
        }
        uint256 D1 = get_D_mem(rates, _balances);
        uint256 token_amount = liquidity_token.totalSupply();
        uint256 diff = 0;
        if (deposit) {
            diff = D1 - D0;
        } else {
            diff = D0 - D1;
        }
        return diff * token_amount / D0;
    }

    function add_liquidity(uint256[4] memory amounts, uint256 min_mint_amount) public nonReentrant {
        require(!is_killed, "contract killed");
        uint256[4] memory fees = ZEROS;
        uint256 _fee = fee * 4 / (4 * (4 - 1));
        uint256[4] memory rates = _stored_rates();
        uint256 D0 = 0;
        uint256[4] memory old_balances = balances;
        if (liquidity_token.totalSupply() > 0) {
            D0 = get_D_mem(rates, old_balances);
        }
        uint256[4] memory new_balances = old_balances;

        for(uint256 i = 0; i < 4; i++) {
            if (liquidity_token.totalSupply() == 0) {
                require(amounts[i] > 0, "amount == 0");
            }
            new_balances[i] = old_balances[i] + amounts[i];
        }

        uint256 D1 = get_D_mem(rates, new_balances);
        require(D1 > D0, "D1 <= D0");

        uint256 D2 = D1;
        if (liquidity_token.totalSupply() > 0) {
            for(uint256 i = 0; i < 4; i++) {
                uint256 ideal_balance = D1 * old_balances[i] / D0;
                uint256 difference = 0;
                if (ideal_balance > new_balances[i]) {
                    difference = ideal_balance = new_balances[i];
                } else {
                    difference = new_balances[i] - ideal_balance;
                }
                fees[i] = _fee * difference / FEE_DENOMINATOR;
                balances[i] = new_balances[i] - fees[i] * admin_fee / FEE_DENOMINATOR;
                new_balances[i] -= fees[i];
            }
            D2 = get_D_mem(rates, new_balances);
        } else {
            balances = new_balances;
        }

        uint256 mint_amount = 0;
        if (liquidity_token.totalSupply() == 0) {
            mint_amount = D1;
        } else {
            mint_amount = liquidity_token.totalSupply() * (D2 - D0) / D0;
        }

        require(mint_amount >= min_mint_amount, "too much slippage");

        for(uint256 i = 0; i < 4; i++) {
            safeTransferFrom(coins[i], msg.sender, address(this), amounts[i]);
        }

        liquidity_token.mint(msg.sender, mint_amount);
        emit AddLiquidity(msg.sender, amounts, fees, D1, liquidity_token.totalSupply());
    }

    function get_y(uint256 i, uint256 j, uint256 x, uint256[4] memory xp) internal view returns(uint256) {
        require((i != j) && (i >= 0) && (j >= 0) && (i < 4) && (j < 4), "illegal vars");
        uint256 D = get_D(xp);
        uint256 c = D;
        uint256 S_ = 0;
        uint256 Ann = A * 4;
        uint256 _x = 0;

        for(uint256 _i = 0; _i < 4; _i++) {
            if (_i == i) {
                _x = x;
            } else if (_i != j) {
                _x = xp[_i];
            } else {
                continue;
            }
            S_ += _x;
            c = c * D / (_x * 4);
        }

        c = c * D / (Ann * 4);
        uint256 b = S_ + D / Ann;
        uint256 y_prev = 0;
        uint256 y = D;

        for(uint256 _i = 0; _i < 255; _i++) {
            y_prev = y;
            y = (y*y + c) / (2 * y + b - D);
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    break;
                }
            } else {
                if (y_prev - y <= 1) {
                    break;
                }
            }
        }

        return y;
    }

    function get_dy(uint256 i, uint256 j, uint256 dx) public view returns(uint256) {
        uint256[4] memory rates = _stored_rates();
        uint256[4] memory xp = _xp(rates);

        uint256 x = xp[i] + dx * rates[i] / PRECISION;
        uint256 y = get_y(i, j, x, xp);
        uint256 dy = (xp[j] - y) * PRECISION / rates[j];
        uint256 _fee = fee * dy / FEE_DENOMINATOR;
        return dy - _fee;
    }

    function get_dx(uint256 i, uint256 j, uint256 dy) public view returns(uint256) {
        uint256[4] memory rates = _stored_rates();
        uint256[4] memory xp = _xp(rates);

        uint256 y = xp[j] - (dy * FEE_DENOMINATOR / (FEE_DENOMINATOR - fee)) * rates[j] / PRECISION;
        uint256 x = get_y(j, i, y, xp);
        uint256 dx = (x - xp[i]) * PRECISION / rates[i];
        return dx;
    }

    function get_dy_underlying(uint256 i, uint256 j, uint256 dx) public view returns(uint256) {
        uint256[4] memory rates = _stored_rates();
        uint256[4] memory xp = _xp(rates);
        uint256[4] memory precisions = PRECISION_MUL;

        uint256 x = xp[i] + dx * precisions[i];
        uint256 y = get_y(i, j, x, xp);
        uint256 dy = (xp[j] - y) / precisions[j];
        uint256 _fee = fee * dy / FEE_DENOMINATOR;
        return dy - _fee;
    }

    function get_dx_underlying(uint256 i, uint256 j, uint256 dy) public view returns(uint256) {
        uint256[4] memory rates = _stored_rates();
        uint256[4] memory xp = _xp(rates);
        uint256[4] memory precisions = PRECISION_MUL;

        uint256 y = xp[j] - (dy * FEE_DENOMINATOR / (FEE_DENOMINATOR - fee)) * precisions[j];
        uint256 x = get_y(j, i, y, xp);
        uint256 dx = (x - xp[i]) / precisions[i];
        return dx;
    }

    function _exchange(uint256 i, uint256 j, uint256 dx, uint256[4] memory rates) internal returns(uint256) {
        require(!is_killed, "I'm dead");
        uint256[4] memory xp = _xp(rates);
        uint256 x = xp[i] + dx * rates[i] / PRECISION;
        uint256 y = get_y(i, j, x, xp); 
        uint256 dy = xp[j] - y;
        uint256 dy_fee = dy * fee / FEE_DENOMINATOR;
        uint256 dy_admin_fee = dy_fee * admin_fee / FEE_DENOMINATOR;
        balances[i] = x * PRECISION / rates[i];
        balances[j] = (y + (dy_fee - dy_admin_fee)) * PRECISION / rates[j];
        uint256 _dy = (dy - dy_fee) * PRECISION / rates[j];

        // manually added to get exchanges to work between decimal coins
        if (PRECISION_MUL[i] < PRECISION_MUL[j]) { // convert from 18 to 6
            _dy = _dy / PRECISION_MUL[j];
        } else if (PRECISION_MUL[i] > PRECISION_MUL[j]) { // convert from 6 to 18
            _dy = _dy * PRECISION_MUL[i];
        }

        return _dy;
    }

    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) public nonReentrant() {
        uint256[4] memory rates = _stored_rates();
        uint256 dy = _exchange(i, j, dx, rates);
        require(dy >= min_dy, "Exchange resulted in fewer coins than expected");
        safeTransferFrom(coins[i], msg.sender, address(this), dx);
        safeTransfer(coins[j], msg.sender, dy);
        emit TokenExchange(msg.sender, i, dx, j, dy);
    }

    function exchange_underlying(uint256 i, uint256 j, uint256 dx, uint256 min_dy) public nonReentrant() {
        uint256[4] memory rates = _stored_rates();
        uint256[4] memory precisions = PRECISION_MUL;
        uint256 rate_i = rates[i] / precisions[i];
        uint256 rate_j = rates[j] / precisions[j];
        uint256 dx_ = dx * PRECISION / rate_i;
        uint256 dy_ = _exchange(i, j, dx_, rates);

        uint256 dy = dy_ * rate_j / PRECISION;
        require(dy >= min_dy, "Exchange resulted in fewer coins than expected 1");

        safeTransferFrom(underlying_coins[i], msg.sender, address(this), dx);
        safeApprove(underlying_coins[i], coins[i], dx);
        yERC20(coins[i]).deposit(dx);
        yERC20(coins[j]).withdraw(dy_);

        dy = mERC20(underlying_coins[j]).balanceOf(address(this));
        require(dy >= min_dy, "Exchange resulted in fewer coins than expected 2");

        safeTransfer(underlying_coins[j], msg.sender, dy);

        emit TokenExchangeUnderlying(msg.sender, i, dx, j, dy);
    }

    function remove_liquidity(uint256 _amount, uint256[4] memory min_amount) public nonReentrant() {
        uint256 total_supply = liquidity_token.totalSupply();
        uint256[4] memory amounts = ZEROS;
        uint256[4] memory fees = ZEROS;

        for(uint256 i = 0; i < 4; i++) {
            uint256 value = balances[i] * _amount / total_supply;
            require(value >= min_amount[i], "Withdrawal resulted in fewer coins than expected");
            balances[i] -= value;
            amounts[i] = value;
            safeTransfer(coins[i], msg.sender, value);
        }

        liquidity_token.burnFrom(msg.sender, _amount);
        emit RemoveLiquidity(msg.sender, amounts, fees, total_supply - _amount);
    }

    function remove_liquidity_imbalance(uint256[4] memory amounts, uint256 max_burn_amount) public nonReentrant() {
        require(!is_killed, "I'm dead");
        require(liquidity_token.totalSupply() > 0, "no token supply");

        uint256 _fee = fee * 4 / 12; //1333333
        uint256[4] memory rates = _stored_rates(); // DAI: 1027929646609989889 USDC: 1027929646609989889 * 1000000000000
        uint256[4] memory old_balances = balances; // DAI: 10000000000000000000
        uint256[4] memory new_balances = old_balances; // DAI_NEW: 9999999999999999990

        uint256 D0 = get_D_mem(rates, old_balances); // 41117185864399595560
        for(uint256 i = 0; i < 4; i++) {
            new_balances[i] -= amounts[i];
        }

        uint256 D1 = get_D_mem(rates, new_balances); // 34231105013938201
        uint256[4] memory fees = ZEROS;

        for(uint256 i = 0; i < 4; i++) {
            uint256 ideal_balance = D1 * old_balances[i] / D0; // 8325254828194953
            uint256 difference = 0;
            if (ideal_balance > new_balances[i]) {
                difference = ideal_balance - new_balances[i];
            } else {
                difference = new_balances[i] - ideal_balance; // 9991674745171805037
            }
            fees[i] = _fee * difference / FEE_DENOMINATOR; // 1332222966300415
            balances[i] = new_balances[i] - fees[i] * admin_fee / FEE_DENOMINATOR;
            new_balances[i] -= fees[i]; // 9998667777033699575
        }
        uint256 D2 = get_D_mem(rates, new_balances); //48841776898676

        uint256 token_amount = (D0 - D2) * liquidity_token.totalSupply() / D0;
        require(token_amount > 0, "no tokens");
        require(token_amount <= max_burn_amount, "too much splippage");

        for(uint256 i = 0; i < 4; i++){
            safeTransfer(coins[i], msg.sender, amounts[i]);
        }

        liquidity_token.burnFrom(msg.sender, token_amount);
        emit RemoveLiquidityImbalance(msg.sender, amounts, fees, D1, liquidity_token.totalSupply());
    }

    /// --- ADMIN ---
    function commit_new_parameters(uint256 amplification, uint256 new_fee, uint256 new_admin_fee) public onlyOwner() {
        require(admin_actions_deadline == 0, "action deadline not 0");
        require(new_admin_fee <= max_admin_fee, "admin fee too high");
        admin_actions_deadline = block.timestamp + admin_actions_delay;
        future_A = amplification;
        future_fee = new_fee;
        future_admin_fee = new_admin_fee;
        emit CommitNewParameters(admin_actions_deadline, future_A, future_fee, future_admin_fee);
    }

    function apply_new_parameters() public {
        require(admin_actions_deadline <= block.timestamp && admin_actions_deadline > 0, "action deadline bad");
        admin_actions_deadline = 0;
        A = future_A;
        fee = future_fee;
        admin_fee = future_admin_fee;
        emit NewParameters(A, fee, admin_fee);
    }

    function revert_new_parameters() public onlyOwner() {
        admin_actions_deadline = 0;
    }

    function commit_transfer_ownership(address _owner) public onlyOwner() {
        require(transfer_ownership_deadline == 0, "transfer deadline bad");
        transfer_ownership_deadline = block.timestamp + admin_actions_delay;
        future_owner = _owner;
        emit CommitNewAdmin(transfer_ownership_deadline, future_owner);
    } 

    function apply_transfer_ownership() public {
        require(transfer_ownership_deadline <= block.timestamp && transfer_ownership_deadline > 0, "transfer deadline bad");
        transfer_ownership_deadline = 0;
        owner = future_owner;
        emit NewAdmin(owner);
    }

    function revert_transfer_ownership() public onlyOwner() {
        transfer_ownership_deadline = 0;
    }

    function withdraw_admin_fees() public onlyOwner() {
        uint256 amount = 0;
        for(uint256 i = 0; i < 4; i++) {
            amount = yERC20(coins[i]).balanceOf(address(this)) - balances[i];
            if(amount > 0) {
                safeTransfer(coins[i], owner, amount);
            }
        }
    }

    function kill_me() public onlyOwner() {
        require(kill_deadline > block.timestamp, "too old to kill");
        is_killed = true;
    }

    function unkill_me() public onlyOwner() {
        is_killed = false;
    }
}