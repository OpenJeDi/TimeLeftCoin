pragma solidity ^0.4.16;

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
    TODO Although we should only mint coins once for each person, a person could have multiple wallets - he just only gets the starting time once on one wallet
*/
contract DaysLeft is owned {
    // Generic properties used by Ethereum
    string public name;
    string public symbol;
    // 18 decimals is the strongly suggested default, avoid changing it
    uint8 public decimals = 18;

    // Version of the contract code
    string public codeVersion = "0.6";

    // The extra balance (in addition to their time balance) of everyone in the system
    // Note: can be negative
    mapping (address => int256) public extraBalanceOf;

    // This generates a public event on the blockchain that will notify clients
    event Transfer(address indexed from, address indexed to, uint256 value);

    // This notifies clients about the amount burnt
    event Burn(address indexed from, uint256 value);

    /** DaysLeft specific */
    
    // Creation date (in seconds since unix epoch) of the contract (set when the contract is deployed and never changed)
    uint public contractCreation;
    
    // The number of days you get at birth (with the decimals already taken care of)
    // TODO No reason this can't be negative
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
        name = tokenName;                                   // Set the name for display purposes
        symbol = tokenSymbol;                               // Set the symbol for display purposes
        contractCreation = now;

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

    /** Calculate balance */
    function balanceOf(address _owner) public view returns (uint256 balance) {
        return uint256(timeTokensLeftOf(_owner) + extraBalanceOf[_owner]);
    }

    // The total supply of time in the contract
    // TODO This doesn't scale very wel...
    function totalSupply() public view returns (uint256 supply) {
        supply = 0;

        for(var i = uint(0); i < addressCount; ++i) {
            var addr = addressOfIndex[i];
            supply += balanceOf(addr);
        }

        return supply;
    }


    /**
     * Internal transfer, only can be called by this contract
       // TODO Make sure the convertion from uint to int doesn't overflow/cut: value can only be max MAX_UINT256/2
     */
    function _transfer(address _from, address _to, uint _value) internal {
        // Prevent transfer to 0x0 address. Use burn() instead
        require(_to != 0x0);
        // Both need to be registered
        require(isRegistered[_from] && isRegistered[_to]);
        // Check if the sender has enough
        // Note: for our DaysLeft contract, a certain amount of time cannot be spent
        // Note: we also check for overflow
        require(balanceOf(_from) >= _value + minBalanceAfterTransfer && _value + minBalanceAfterTransfer > _value);
        // Check for overflows
        require(balanceOf(_to) + _value > balanceOf(_to));
        // Subtract from the sender
        extraBalanceOf[_from] -= int(_value);
        // Add the same to the recipient
        extraBalanceOf[_to] += int(_value);
        Transfer(_from, _to, _value);
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
        
        require(balanceOf(msg.sender) >= _value + minBalanceAfterTransfer);   // Check if the sender has enough
        require(_value + minBalanceAfterTransfer > _value); // Check for overflow
        extraBalanceOf[msg.sender] -= int256(_value);            // Subtract from the sender
        Burn(msg.sender, _value);
        return true;
    }
    
    /** DaysLeft specific code start */
    
    // Note: for now this is only for the owner, until we have a proper way of automatically verifying the birth date
    // TODO When you do this before a necessary time burn is performed, the user will lose days when the time burn is performed! To by in sync with the rest of the users, we should add the tokens to be burned in this step
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
        
        // Notify clients
        // Note: we send a Burn event to indicate how many time the new user has already spent
        Burn(_newAddress, balanceAtBirth - uint256(timeTokensLeft(_birth)));
        AddressRegistered(_newAddress, _birth, balanceOf(_newAddress));
    }
    /** Const function to check if you are registered */
    function amIRegistered() public view returns (bool) {
        return isRegistered[msg.sender];
    }

    /** The time tokens left
        Note: can be negative
    */
    function timeTokensLeft(uint birthDay) public view returns (int) {
        // Cannot be born in the future
        if(birthDay > now)
            return 0;

        // Note: we first multiply so we have a more accurate balance
        //return int(balanceAtBirth) - int((now - birthDay) / 1 days * 10 ** uint256(decimals));
        return int(balanceAtBirth) - int((now - birthDay) * 10 ** uint256(decimals)) / 1 days;
    }
    function timeTokensLeftOf(address who) public view returns (int) {
        if(!isRegistered[who])
            return 0;

        var birthDay = birthOf[who];
        return timeTokensLeft(birthDay);
    }

    ///// Development Functionality /////

    // Sent when the owner has changed the extra balance of a wallet
    event OwnerChangedExtraBalance(address indexed addr, int oldExtra, int newExtra);

    function setExtraBalance(address _address, int _extraBalance) onlyOwner public {
        // Needs to be registered
        //require(isRegistered[_address]);

        // Change the balance
        var oldExtraBalance = extraBalanceOf[_address];
        extraBalanceOf[_address] = _extraBalance;

        // Send event
        OwnerChangedExtraBalance(_address, oldExtraBalance, _extraBalance);
    }
}
