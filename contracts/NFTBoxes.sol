pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../interfaces/IVendingMachine.sol";
import "./Controller.sol";

contract NFTBoxes is ERC721("NFT Boxes", "BOX"), Controller {

	struct BoxMould{
		uint8				live; // bool
		uint8				shared; // bool
		uint128				maxEdition;
		uint128				currentEditionCount;
		uint256				price;
		uint256[]			ids;
		address payable[]	artists;
		uint256[]			shares;
		string				name;
	}

	struct Box {
		uint256				boxId;
		uint256				edition;
	}

	IVendingMachine public	vendingMachine;
	uint256 public			boxMouldCount;

	uint256 constant public TOTAL_SHARES = 1000;

	mapping(uint256 => BoxMould) public	boxMoulds;
	mapping(uint256 =>  Box) public	boxes;
	mapping(uint256 => bool) public lockedBoxes;

	mapping(address => uint256) public teamShare;
	address payable[] public team;

	event BoxMouldCreated(uint256 id);
	event BoxBought(uint256 indexed boxMould, uint256 boxEdition, uint256 tokenId);

	function updateURI(string memory newURI) public onlyOwner {
		_setBaseURI(newURI);
	}

	function addTeamMember(address payable _member) external onlyOwner {
		for (uint256 i = 0; i < team.length; i++)
			require( _member != team[i], "NFTBoxes: members exists already");
		team.push(_member);
	}

	function removeTeamMember(address payable _member) external onlyOwner {
		for (uint256 i = 0; i < team.length; i++)
			if (team[i] == _member) {
				delete teamShare[_member];
				team[i] = team[team.length - 1];
				team.pop();
			}
	}

	function setTeamShare(address _member, uint _share) external onlyOwner {
		require(_share <= TOTAL_SHARES, "NFTBoxes: share must be below 1000");
		for (uint256 i = 0; i < team.length; i++)
			if (team[i] == _member)
				teamShare[_member] = _share;
	}

	function setLockOnBox(uint256 _id, bool _lock) external onlyOwner {
		require(_id <= boxMouldCount && _id > 0, "NFTBoxes: Mould ID does not exist.");
		lockedBoxes[_id] = _lock;
	}

	function createBoxMould(
		uint128 _max,
		uint256 _price,
		uint256[] memory _ids,
		address payable[] memory _artists,
		uint256[] memory _shares,
		string memory _name)
		external
		onlyOwner {
		require(_artists.length == _shares.length, "NFTBoxes: arrays are not of same length.");
		boxMoulds[boxMouldCount + 1] = BoxMould({
			live: uint8(0),
			shared: uint8(0),
			maxEdition: _max,
			currentEditionCount: 0,
			price: _price,
			ids: _ids,
			artists: _artists,
			shares: _shares,
			name: _name
		});
		boxMouldCount++;
	}

	function removeArtist(uint256 _id, address payable _artist) external onlyOwner {
		BoxMould storage boxMould = boxMoulds[_id];
		require(_id <= boxMouldCount && _id > 0, "NFTBoxes: Mould ID does not exist.");
		for (uint256 i = 0; i < boxMould.artists.length; i++) {
			if (boxMould.artists[i] == _artist) {
				boxMould.artists[i] = boxMould.artists[boxMould.artists.length - 1];
				boxMould.artists.pop();
				boxMould.shares[i] = boxMould.shares[boxMould.shares.length - 1];
				boxMould.shares.pop();
			}
		}
	}
	
	function addArtists(uint256 _id, address payable _artist, uint256 _share) external onlyOwner {
		BoxMould storage boxMould = boxMoulds[_id];
		require(_id <= boxMouldCount && _id > 0, "NFTBoxes: Mould ID does not exist.");
		boxMould.artists.push(_artist);
		boxMould.shares.push(_share);
	}

	// dont even need this tbh?
	function getArtistRoyalties(uint256 _id) external view returns (address payable[] memory artists, uint256[] memory royalties) {
		require(_id <= boxMouldCount && _id > 0, "NFTBoxes: Mould ID does not exist.");
		BoxMould memory boxMould = boxMoulds[_id];
		artists = boxMould.artists;
		royalties = boxMould.shares;
	}

	function buyManyBoxes(uint256 _id, uint128 _quantity) external payable {
		BoxMould storage boxMould = boxMoulds[_id];
		require(_id <= boxMouldCount && _id > 0, "NFTBoxes: Mould ID does not exist.");
		require(boxMould.price.mul(_quantity) == msg.value, "NFTBoxes: Wrong total price.");
		require(boxMould.currentEditionCount + _quantity <= boxMould.maxEdition, "NFTBoxes: Minting too many boxes.");

		for (uint128 i = 0; i < _quantity; i++)
			_buy(boxMould, _id, i);
		boxMould.currentEditionCount += _quantity;
		if (boxMould.currentEditionCount == boxMould.maxEdition)
			boxMould.live = uint8(1);
	}

	function _buy(BoxMould storage boxMould, uint256 _id, uint256 _new) internal {
		boxes[totalSupply()] = Box(_id, boxMould.currentEditionCount + _new);
		//safe mint?
		emit BoxBought(_id, boxMould.currentEditionCount + _new, totalSupply());
		_mint(msg.sender, totalSupply());
	}

	// close a sale if not sold out
	function closeBox(uint256 _id) external onlyOwner {
		BoxMould storage boxMould = boxMoulds[_id];
		require(_id <= boxMouldCount && _id > 0, "NFTBoxes: Mould ID does not exist.");
		boxMould.live = uint8(1);
	}

	function setVendingMachine(address _machine) external onlyOwner {
		vendingMachine = IVendingMachine(_machine);
	}

	function distributeOffchain(uint256 _id, address[][] memory _recipients) external onlyOwner {
		BoxMould memory boxMould= boxMoulds[_id];
		require(boxMould.live == 1, "NTFBoxes: Box is still live, cannot start distribution");
		require (_recipients[0].length == boxMould.ids.length, "NFTBoxes: Wrong array size.");

		// i is batch number
		for (uint256 i = 0; i < _recipients.length; i++) {
			// j is for the index of nft ID to send
			for (uint256 j = 0;j <  _recipients[0].length; j++)
				vendingMachine.JOYtoyMachineFor(boxMould.ids[j], _recipients[i][j]);
		}
	}

	function distributeShares(uint256 _id) external {
		BoxMould storage boxMould= boxMoulds[_id];
		require(_id <= boxMouldCount && _id > 0, "NFTBoxes: Mould ID does not exist.");
		require(boxMould.live == 1 && boxMould.shared == 0,  "NFTBoxes: cannot distribute shares yet.");
		require(is100(_id), "NFTBoxes: shares do not add up to 100%.");

		boxMould.shared = 1;
		uint256 rev = uint256(boxMould.currentEditionCount).mul(boxMould.price);
		uint256 share;
		for (uint256 i = 0; i < team.length; i++) {
			share = rev.mul(teamShare[team[i]]).div(TOTAL_SHARES);
			team[i].transfer(share);
		}
		for (uint256 i = 0; i < boxMould.artists.length; i++) {
			share = rev.mul(boxMould.shares[i]).div(TOTAL_SHARES);
			boxMould.artists[i].transfer(share);
		}
	}

	function is100(uint256 _id) internal returns(bool) {
		BoxMould storage boxMould= boxMoulds[_id];
		uint256 total;
		for (uint256 i = 0; i < team.length; i++) {
			total = total.add(teamShare[team[i]]);
		}
		for (uint256 i = 0; i < boxMould.shares.length; i++) {
			total = total.add(boxMould.shares[i]);
		}
		return total == TOTAL_SHARES;
	}

	function _getNewSeed(bytes32 _seed) public pure returns (bytes32) {
		return keccak256(abi.encodePacked(_seed));
	}

	function getIdsLength(uint256 _id) external view returns (uint256) {
		return boxMoulds[_id].ids.length;
	}

	function _transfer(address from, address to, uint256 tokenId) internal override {
		Box memory box = boxes[tokenId];
		require(!lockedBoxes[box.boxId], "NFTBoxes: Box is locked");
		super._transfer(from, to, tokenId);
	}
}
