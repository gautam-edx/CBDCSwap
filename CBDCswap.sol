// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract CBDCSwap is Ownable, Pausable {

    struct Order {
        address user;
        address tokenGive;
        uint256 amountGive;
        address tokenGet;
        uint256 amountGet;
        bool active;
    }

    mapping(uint256 => Order) public orders;
    uint256 public orderCount;
    uint256 public creationFee;

    event OrderCreated(uint256 orderId, address user, address tokenGive, uint256 amountGive, address tokenGet, uint256 amountGet);
    event OrderSwapped(uint256 orderId, address user, address tokenGive, uint256 amountGive, address tokenGet, uint256 amountGet);
    event OrderCancelled(uint256 orderId, address user);

    constructor(uint256 _creationFee) Ownable(msg.sender)  {
        creationFee = _creationFee;
    }

    function setCreationFee(uint256 _fee) external onlyOwner {
        creationFee = _fee;
    }

    function createOrder(address _tokenGive, uint256 _amountGive, address _tokenGet, uint256 _amountGet) payable  external whenNotPaused {
        require(msg.value == creationFee, "Incorrect fee amount");

        require(_amountGive > 0 && _amountGet > 0, "Invalid amount");
        require(IERC20(_tokenGive).balanceOf(msg.sender) >= _amountGive, "Insufficient balance");
        require(IERC20(_tokenGive).allowance(msg.sender, address(this)) >= _amountGive, "Not approved");
        
        uint256 orderId = orderCount++;
        orders[orderId] = Order(msg.sender, _tokenGive, _amountGive, _tokenGet, _amountGet, true);
        
        emit OrderCreated(orderId, msg.sender, _tokenGive, _amountGive, _tokenGet, _amountGet);
        
        // Decrease the allowance after the order is created
        require(IERC20(_tokenGive).transferFrom(msg.sender, address(this), _amountGive), "Token transfer failed");
    }

    function swap(uint256 _orderId, uint256 _amount) external whenNotPaused {
        Order storage order = orders[_orderId];
        require(order.active, "Order does not exist or inactive");

        // Ensure the user has enough balance of the token they are giving
       // require(IERC20(order.tokenGet).balanceOf(msg.sender) >= _amount * order.amountGet / order.amountGive, "Insufficient balance");

        // Calculate the corresponding amount of tokenGet based on the ratio
        uint256 amountGetPartial = _amount * order.amountGet / order.amountGive;

        // Transfer tokens from the user to the contract
        require(IERC20(order.tokenGet).transferFrom(msg.sender, address(this), amountGetPartial), "Token transfer failed");

        // Transfer tokens from the contract to the user
        require(IERC20(order.tokenGet).transfer(order.user, amountGetPartial), "Token transfer failed");

        // Transfer tokens to the order user
        require(IERC20(order.tokenGive).transfer(msg.sender, _amount), "Token transfer failed");

        // Update the amounts in the order
        order.amountGive -= _amount;
        order.amountGet -= amountGetPartial;

        // If the order is completely filled, mark it as completed
        if (order.amountGive == 0) {
            order.active = false;
        }

        emit OrderSwapped(_orderId, order.user, order.tokenGive, _amount, order.tokenGet, amountGetPartial);
    }

    function calAmountToAprove(uint256 _orderId, uint256 _amountWant) public view returns(uint){
         Order storage order = orders[_orderId];
        uint256 amountGivePartial = _amountWant * order.amountGet / order.amountGive;
        return  amountGivePartial;
    }
    

    function cancelOrder(uint256 _orderId) external whenNotPaused {
        Order storage order = orders[_orderId];
        require(msg.sender == order.user, "Only order creator can cancel the order");
        require(order.active, "Order is already inactive");

        // Check if the order got executed completely
        if (order.amountGive == 0) {
            revert("Order cannot be cancelled as it's already completely filled");
        }
        
        require(IERC20(order.tokenGive).transfer(msg.sender, order.amountGive), "Token transfer failed");
    

        // Mark the order as inactive
        order.active = false;

        emit OrderCancelled(_orderId, msg.sender);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

     function searchOrderByToken(address _token) external view returns (uint256[] memory) {
        uint256 count;
        for (uint256 i = 0; i < orderCount; i++) {
            if (orders[i].active && (orders[i].tokenGive == _token || orders[i].tokenGet == _token)) {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 index;
        for (uint256 i = 0; i < orderCount; i++) {
            if (orders[i].active && (orders[i].tokenGive == _token || orders[i].tokenGet == _token)) {
                result[index++] = i;
            }
        }

        return result;
    }

    function getOrderDetails(uint256 _orderId) external view returns (address, address, uint256, address, uint256, bool) {
        Order memory order = orders[_orderId];
        require(order.active, "Order does not exist or inactive");
        return (order.user, order.tokenGive, order.amountGive, order.tokenGet, order.amountGet, order.active);
    }
}

