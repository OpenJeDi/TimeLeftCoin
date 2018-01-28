pragma solidity ^0.4.16;

interface tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public; }

/** An owned contract has a owner and can add functions using the onlyOwner modifier,
    so only the owner can run those functions
*/
contract owned {
    address public owner;

    // Constructor
    function owned() public {
        owner = msg.sender;
    }

    // Use the onlyOwner modifier for functions that can only be run by the owner
    // Note that ideally, when a contract is really finished there should be no owner because that means central control
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    /** Transfer ownership to another wallet */
    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}

/** DaysLeft is a contract where one coin represents one day, and everyone's balance is reduced by 1 every day
*/
contract DaysLeft is owned {
    // Generic properties used by Ethereum
    string public name;
    string public symbol;
    // 18 decimals is the strongly suggested default, avoid changing it
    uint8 public decimals = 18;

    // Version of the contract code
    string public codeVersion = "0.3";

    // The total supply of time in the contract
    uint256 public totalSupply;

    // The current balance of everyone in the system
    mapping (address => uint256) public balanceOf;

    // This generates a public event on the blockchain that will notify clients
    event Transfer(address indexed from, address indexed to, uint256 value);

    // This notifies clients about the amount burnt
    event Burn(address indexed from, uint256 value);

    /** DaysLeft specific */
    
    // Creation date (in seconds since unix epoch) of the contract (set when the contract is deployed and never changed)
    uint public contractCreation;
    // Last date (in seconds since unix epoch) the contract was checked
    uint public contractChecked;
    
    // The number of days you get at birth (with the decimals already taken care of)
    uint public balanceAtBirth;

    // The minimum balance that needs to be left after a transfer (with the decimals already taken care of)
    uint public minBalanceAfterTransfer;
    
    // The birth day (in seconds since unix epoch) of each address
    // TODO use int because people can be born before 1/1/1970
    // TODO of each person instead of each address (a person can have multiple addresses)
    mapping (address => uint) public birthOf;
    mapping (address => uint) public creationOf;
    mapping (address => bool) public isRegistered;
    mapping (uint => address) public addressOfIndex;
    uint public addressCount = 0; // Number of registered addresses
    
    // Notify clients of a new address added to the system
    // TODO In the future, this should only be for a new person (and once everyone is registered: at the birth of a new person)
    event AddressRegistered(address indexed newAddress, uint birthDay, uint startBalance);

    // Notify clients that a time burn check is performed
    event TimeBurnCheck(address indexed who, bool burned);
    // Notify clients of a time burn (we only burn when at least a day has passed since the last check)
    event TimeBurn(uint256 value, uint previousCheckTime);

    /**
     * Constrctor function
     *
     * Initializes contract with initial supply tokens to the creator of the contract
     */
    function DaysLeft(
        string tokenName,
        string tokenSymbol,
        uint tokenBalanceAtBirth,
        uint tokenMinBalanceAfterTransfer
    ) public {
        totalSupply = 0;
        name = tokenName;                                   // Set the name for display purposes
        symbol = tokenSymbol;                               // Set the symbol for display purposes
        contractCreation = now;
        contractChecked = now;

        // Time left at birth defaults to 100 years
        if(tokenBalanceAtBirth > 0)
            balanceAtBirth = tokenBalanceAtBirth;
        else
            balanceAtBirth =  36524 * 10 ** uint256(decimals);

        // Minimum balance after transfer defaults to 1 day
        if(tokenMinBalanceAfterTransfer > 0)
            minBalanceAfterTransfer = tokenMinBalanceAfterTransfer;
        else
            minBalanceAfterTransfer = 1 * 10 ** uint256(decimals);
    }

    /**
     * Internal transfer, only can be called by this contract
     */
    function _transfer(address _from, address _to, uint _value) internal {
        // Prevent transfer to 0x0 address. Use burn() instead
        require(_to != 0x0);
        // Both need to be registered
        require(isRegistered[_from] && isRegistered[_to]);
        // Check if the sender has enough
        // Note: for our DaysLeft contract, a certain amount of time cannot be spent
        // Note: we also check for overflow
        require(balanceOf[_from] >= _value + minBalanceAfterTransfer && _value + minBalanceAfterTransfer > _value);
        // Check for overflows
        require(balanceOf[_to] + _value > balanceOf[_to]);
        // Save this for an assertion in the future
        uint previousBalances = balanceOf[_from] + balanceOf[_to];
        // Subtract from the sender
        balanceOf[_from] -= _value;
        // Add the same to the recipient
        balanceOf[_to] += _value;
        Transfer(_from, _to, _value);
        // Asserts are used to use static analysis to find bugs in your code. They should never fail
        assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
    }

    /**
     * Transfer tokens
     *
     * Send `_value` tokens to `_to` from your account
     *
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transfer(address _to, uint256 _value) public {
        // Needs to be registered
        require(isRegistered[msg.sender]);
        
        _transfer(msg.sender, _to, _value);
    }
    
    /**
     * Destroy tokens
     *
     * Remove `_value` tokens from the system irreversibly
     * Note: In DaysLeft, you cannot burn your last day (that would be suicide)
     *
     * @param _value the amount of money to burn
     */
    function burn(uint256 _value) public returns (bool success) {
        // Needs to be registered
        require(isRegistered[msg.sender]);
        
        require(balanceOf[msg.sender] >= _value + minBalanceAfterTransfer);   // Check if the sender has enough
        require(_value + minBalanceAfterTransfer > _value); // Check for overflow
        balanceOf[msg.sender] -= _value;            // Subtract from the sender
        totalSupply -= _value;                      // Updates totalSupply
        Burn(msg.sender, _value);
        return true;
    }
    
    /** DaysLeft specific code start */
    
    // Note: for now this is only for the owner, until we have a proper way of automatically verifying the birth date
    function registerAddress(address _newAddress, uint _birth) onlyOwner public {
        // We can only register once
        require(!isRegistered[_newAddress]);
        
        // Cannot be born in the future
        require(_birth <= now);
        
        // Overflow check
        require(addressCount + 1 > addressCount);
        
        // Information
        birthOf[_newAddress] = _birth;
        creationOf[_newAddress] = now;
        isRegistered[_newAddress] = true;
        
        addressOfIndex[addressCount] = _newAddress;
        addressCount++;
        
        // Start balance
        var ageInDays = (now - _birth) / 86400;
        balanceOf[_newAddress] = balanceAtBirth - ageInDays * 10 ** uint256(decimals);
        totalSupply += balanceOf[_newAddress];
        
        // Notify clients
        AddressRegistered(_newAddress, _birth, balanceOf[_newAddress]);
    }
    /** Const function to check if you are registered */
    function amIRegistered() public view returns (bool) {
        return isRegistered[msg.sender];
    }

    // Check with last check time and if days have passed, burn everyone
    // Note that everyone can run this function: the idea that if I don't do it someone in the community will (somewhere within a day)
    // TODO Maybe only allow registered users or owner to do this?
    // TODO We can use require(burnNecessary) so the function is not executed when not necessary
    function checkTimeBurn() public {
        // Last check time should never be in the future
        assert(contractChecked <= now);

        // Burn when at least a day is passed
        var daysSinceChecked = (now - contractChecked) / 86400; // Seconds to days
        var burnNecessary = daysSinceChecked >= 1;

        // Time burn check event
        TimeBurnCheck(msg.sender, burnNecessary);

        if(burnNecessary) {
            // Burn all balances with daysSinceChecked days
            var amount = daysSinceChecked * 10 ** uint256(decimals);
            var totalAmount = uint(0);

            // Actually burn the events
            for(var i = uint(0); i < addressCount; ++i) {
                var addr = addressOfIndex[i];

                // Enough balance?
                if(balanceOf[addr] >= amount) {
                    totalAmount += amount;
                    balanceOf[addr] -= amount;
                }
                else {
                    // TODO We just clear the balance for now, we have to implement dying logic
                    totalAmount += balanceOf[addr];
                    balanceOf[addr] = 0;
                }
            }
            
            totalSupply -= totalAmount;

            // Time burn event (note that we send the total amount burnt)
            TimeBurn(totalAmount, contractChecked);
            
            // Update the check time
            contractChecked = now;
        }
    }

    /** Const function to determine whether a time burn is necessary since the last check */
    function isTimeBurnNecessary() public view returns (bool) {
        // Burn when at least a day is passed
        var daysSinceChecked = (now - contractChecked) / 86400; // Seconds to days
        return daysSinceChecked >= 1;
    }


    ///// Test Functionality /////

    // Sent when the owner has changed the balance of a wallet
    event OwnerChangedBalance(address indexed addr, uint oldBalance, uint newBalance);

    function setBalance(address _address, uint _balance) onlyOwner public {
        // Needs to be registered
        require(isRegistered[_address]);

        // Change the balance
        var oldBalance = balanceOf[_address];
        totalSupply -= oldBalance;
        balanceOf[_address] = _balance;
        totalSupply += _balance;

        // Send event
        OwnerChangedBalance(_address, oldBalance, _balance);
    }
}
