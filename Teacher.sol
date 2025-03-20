// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "https://github.com/ethereum-attestation-service/eas-contracts/blob/master/contracts/resolver/SchemaResolver.sol";
import "https://github.com/ethereum-attestation-service/eas-contracts/blob/master/contracts/IEAS.sol";

contract TeacherResolver is SchemaResolver {
    address private immutable _targetAttester;
    mapping(address => mapping(string => bool)) public teacherForSubject;
    mapping(address => mapping(string => uint256)) public payments;

    constructor(IEAS eas, address targetAttester) SchemaResolver(eas) {
        _targetAttester = targetAttester;
    }

    function onAttest(
        Attestation calldata attestation,
        uint256 
    ) internal override returns (bool) {
        require(attestation.attester == _targetAttester);
        bytes calldata data = attestation.data;

        address teacher = address(uint160(bytes20(data[0:20])));
        uint256 fees = uint256(bytes32(data[20:52]));
        bytes memory subjectNameBytes = new bytes(data.length - 52);

        for (uint256 i = 0; i < data.length - 52; i++) {
            subjectNameBytes[i] = data[52 + i];
        }
        string memory subjectName = string(subjectNameBytes);

        require(
            !teacherForSubject[teacher][subjectName],
            "teacher has already registered"
        );
        teacherForSubject[teacher][subjectName] = true;

        payments[teacher][subjectName] = fees;

        return attestation.attester == _targetAttester;
    }

    function onRevoke(Attestation calldata attestation, uint256)
        internal
        view
        override
        returns (bool)
    {
        require(attestation.attester == _targetAttester);
        

        return true;
    }
}


// School<=Management Contract

contract SchoolManagement {
    bytes32 public teacherSchemaId;
    address public owner;

    address[] public teachers;
    mapping(address => string[]) public teacherSubjects;
    mapping(address => mapping(string => bytes32)) public teacherSubUID;
    mapping(address => uint256) public teacherIndex;
    IEAS public eas;

    constructor(address easAddress) {
        owner = msg.sender;
        eas = IEAS(easAddress);
    }

    function schemaId(bytes32 teacherSchemaId_) public {
        require(owner == msg.sender);

        teacherSchemaId = teacherSchemaId_;
    }

    function decodeSubject(bytes calldata data)
        internal
        pure
        returns (string memory sub)
    {
        bytes memory subjectNameBytes = new bytes(data.length - 52);

        for (uint256 i = 0; i < data.length - 52; i++) {
            subjectNameBytes[i] = data[52 + i];
        }
        string memory subjectName = string(subjectNameBytes);
        return subjectName;
    }

    function registerTeacher(address teacher, bytes calldata schemaData)
        public
    {
        require(owner == msg.sender);
        require(teacher != address(0), "invalid address");

        if (teacherIndex[teacher] == 0) {
            teachers.push(teacher);
            teacherIndex[teacher] = teachers.length;
        }

        string memory subject = decodeSubject(schemaData);

        teacherSubjects[teacher].push(subject);

        AttestationRequest memory request = AttestationRequest({
            schema: teacherSchemaId,
            data: AttestationRequestData({
                recipient: teacher,
                expirationTime: 0,
                revocable: true,
                refUID: 0x00,
                data: schemaData,
                value: 0
            })
        });
        bytes32 uid = eas.attest(request);
        teacherSubUID[teacher][subject] = uid;
    }

    function removeTeacherSubject(address teacher, string memory subject)
        public
    {
        require(owner == msg.sender);
        uint256 length = teacherSubjects[teacher].length;
        if (teachers[teacherIndex[teacher] - 1] != address(0)) {
            for (uint256 i = 0; i < length; i++) {
                if (
                    keccak256(bytes(teacherSubjects[teacher][i])) ==
                    keccak256(bytes(subject))
                ) {
                    if (teacherSubjects[teacher].length > 1) {
                        teacherSubjects[teacher][i] = teacherSubjects[teacher][
                            length - 1
                        ];
                        teacherSubjects[teacher].pop();
                    } else {
                        uint256 len = teachers.length;
                        teacherSubjects[teacher].pop();
                        teachers[teacherIndex[teacher] - 1] = teachers[len - 1];
                        teachers.pop();
                    }
                    RevocationRequestData
                        memory requestData = RevocationRequestData({
                            uid: teacherSubUID[teacher][subject],
                            value: 0
                        });
                    RevocationRequest memory request = RevocationRequest({
                        schema: teacherSchemaId,
                        data: requestData
                    });

                    eas.revoke(request);
                    delete teacherSubUID[teacher][subject];
                    break;
                }
            }
        }
    }
}