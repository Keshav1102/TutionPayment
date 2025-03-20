// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "https://github.com/ethereum-attestation-service/eas-contracts/blob/master/contracts/resolver/SchemaResolver.sol";
import "https://github.com/ethereum-attestation-service/eas-contracts/blob/master/contracts/IEAS.sol";

contract StudentResolver is SchemaResolver {
    address private immutable _targetAttester;
    
    // Mapping to track student enrollment in subjects
    mapping(address => mapping(address => mapping(string => uint256))) public studentEnrollmentExpiry; // student -> teacher -> subject -> expiry timestamp
    
    constructor(IEAS eas, address targetAttester) SchemaResolver(eas) {
        _targetAttester = targetAttester;
    }

    function onAttest(
        Attestation calldata attestation,
        uint256 
    ) internal override returns (bool) {
        require(attestation.attester == _targetAttester, "Invalid attester");
        bytes calldata data = attestation.data;

        // Parse data: student address (20 bytes) + teacher address (20 bytes) + validity period in seconds (32 bytes) + subject name
        address student = address(uint160(bytes20(data[0:20])));
        address teacher = address(uint160(bytes20(data[20:40])));
        uint256 validityPeriod = uint256(bytes32(data[40:72])); // in seconds
        
        bytes memory subjectNameBytes = new bytes(data.length - 72);
        for (uint256 i = 0; i < data.length - 72; i++) {
            subjectNameBytes[i] = data[72 + i];
        }
        string memory subjectName = string(subjectNameBytes);
        
        // Set enrollment expiry time
        studentEnrollmentExpiry[student][teacher][subjectName] = block.timestamp + validityPeriod;
        
        return true;
    }

    function onRevoke(Attestation calldata attestation, uint256)
        internal
        override
        returns (bool)
    {
        require(attestation.attester == _targetAttester, "Invalid attester");
        bytes calldata data = attestation.data;
        
        // Parse data
        address student = address(uint160(bytes20(data[0:20])));
        address teacher = address(uint160(bytes20(data[20:40])));
        
        bytes memory subjectNameBytes = new bytes(data.length - 72);
        for (uint256 i = 0; i < data.length - 72; i++) {
            subjectNameBytes[i] = data[72 + i];
        }
        string memory subjectName = string(subjectNameBytes);
        
        // Reset enrollment expiry
        studentEnrollmentExpiry[student][teacher][subjectName] = 0;
        
        return true;
    }
    
    // Check if a student's enrollment is valid
    function isEnrollmentValid(address student, address teacher, string memory subject) external view returns (bool) {
        uint256 expiryTime = studentEnrollmentExpiry[student][teacher][subject];
        return expiryTime > block.timestamp;
    }
    
    // Get remaining validity period in seconds
    function getRemainingValidity(address student, address teacher, string memory subject) external view returns (uint256) {
        uint256 expiryTime = studentEnrollmentExpiry[student][teacher][subject];
        if (expiryTime <= block.timestamp) {
            return 0;
        }
        return expiryTime - block.timestamp;
    }
}

contract StudentManagement {
    bytes32 public studentSchemaId;
    address public owner;
    IEAS public eas;
    
    // Teacher resolver contract reference
    address public teacherResolverAddress;
    
    // Student data structures
    struct StudentEnrollment {
        address teacher;
        string subject;
        uint256 expiryTime;
        bytes32 attestationUID;
    }
    
    mapping(address => StudentEnrollment[]) public studentEnrollments;
    mapping(address => mapping(address => mapping(string => uint256))) public enrollmentIndex; // student -> teacher -> subject -> index+1
    
    event StudentEnrolled(address indexed student, address indexed teacher, string subject, uint256 expiryTime);
    event EnrollmentRevoked(address indexed student, address indexed teacher, string subject);
    
    constructor(address easAddress) {
        owner = msg.sender;
        eas = IEAS(easAddress);
    }
    
    function setSchemaId(bytes32 _studentSchemaId) external {
        require(msg.sender == owner, "Only owner can set schema ID");
        studentSchemaId = _studentSchemaId;
    }
    
    function setTeacherResolverAddress(address _teacherResolverAddress) external {
        require(msg.sender == owner, "Only owner can set teacher resolver");
        teacherResolverAddress = _teacherResolverAddress;
    }
    
    // Enroll a student in a subject with a specific teacher
    function enrollStudent(address student, address teacher, string calldata subject, uint256 validityPeriod) external payable {
        // Check if the teacher is registered for this subject
        ITeacherResolver teacherResolver = ITeacherResolver(teacherResolverAddress);
        require(teacherResolver.teacherForSubject(teacher, subject), "Teacher not registered for this subject");
        
        // Get the required payment amount
        uint256 requiredFee = teacherResolver.payments(teacher, subject);
        require(msg.value >= requiredFee, "Insufficient payment");
        
        // Create attestation data
        bytes memory attestationData = abi.encodePacked(
            student,
            teacher,
            validityPeriod,
            bytes(subject)
        );
        
        // Create attestation request
        AttestationRequest memory request = AttestationRequest({
            schema: studentSchemaId,
            data: AttestationRequestData({
                recipient: student,
                expirationTime: uint64(block.timestamp + validityPeriod),
                revocable: true,
                refUID: 0x00,
                data: attestationData,
                value: 0
            })
        });
        
        // Attest the enrollment
        bytes32 uid = eas.attest(request);
        
        // Store enrollment data
        uint256 index = enrollmentIndex[student][teacher][subject];
        if (index == 0) {
            // New enrollment
            studentEnrollments[student].push(StudentEnrollment({
                teacher: teacher,
                subject: subject,
                expiryTime: block.timestamp + validityPeriod,
                attestationUID: uid
            }));
            enrollmentIndex[student][teacher][subject] = studentEnrollments[student].length;
        } else {
            // Update existing enrollment
            studentEnrollments[student][index - 1] = StudentEnrollment({
                teacher: teacher,
                subject: subject,
                expiryTime: block.timestamp + validityPeriod,
                attestationUID: uid
            });
        }
        
        // Transfer payment to teacher
        payable(teacher).transfer(msg.value);
        
        emit StudentEnrolled(student, teacher, subject, block.timestamp + validityPeriod);
    }
    
    // Revoke a student's enrollment (can be called by owner or automatically when validity expires)
    function revokeEnrollment(address student, address teacher, string memory subject) public {
        require(msg.sender == owner || msg.sender == student || msg.sender == teacher, "Unauthorized");
        
        uint256 index = enrollmentIndex[student][teacher][subject];
        require(index > 0, "Enrollment not found");
        
        StudentEnrollment memory enrollment = studentEnrollments[student][index - 1];
        
        // Create revocation request
        RevocationRequest memory request = RevocationRequest({
            schema: studentSchemaId,
            data: RevocationRequestData({
                uid: enrollment.attestationUID,
                value: 0
            })
        });
        
        // Revoke the attestation
        eas.revoke(request);
        
        // Remove enrollment data
        uint256 lastIndex = studentEnrollments[student].length - 1;
        if (index - 1 != lastIndex) {
            studentEnrollments[student][index - 1] = studentEnrollments[student][lastIndex];
            // Update index mapping for the moved enrollment
            enrollmentIndex[student][studentEnrollments[student][index - 1].teacher][studentEnrollments[student][index - 1].subject] = index;
        }
        studentEnrollments[student].pop();
        delete enrollmentIndex[student][teacher][subject];
        
        emit EnrollmentRevoked(student, teacher, subject);
    }
    
    // Auto-revoke expired enrollments
    function revokeExpiredEnrollments(address student) external {
        for (uint256 i = 0; i < studentEnrollments[student].length; i++) {
            if (studentEnrollments[student][i].expiryTime <= block.timestamp) {
                revokeEnrollment(
                    student,
                    studentEnrollments[student][i].teacher,
                    studentEnrollments[student][i].subject
                );
                // Since we're removing elements, we need to adjust the counter
                i--;
            }
        }
    }
    
    // Check if enrollment is valid
    function isEnrollmentValid(address student, address teacher, string calldata subject) external view returns (bool) {
        uint256 index = enrollmentIndex[student][teacher][subject];
        if (index == 0) return false;
        
        return studentEnrollments[student][index - 1].expiryTime > block.timestamp;
    }
    
    // Get remaining validity period in seconds
    function getRemainingValidity(address student, address teacher, string calldata subject) external view returns (uint256) {
        uint256 index = enrollmentIndex[student][teacher][subject];
        if (index == 0) return 0;
        
        uint256 expiryTime = studentEnrollments[student][index - 1].expiryTime;
        if (expiryTime <= block.timestamp) return 0;
        
        return expiryTime - block.timestamp;
    }
}

// Interface for TeacherResolver to avoid circular dependencies
interface ITeacherResolver {
    function teacherForSubject(address teacher, string memory subject) external view returns (bool);
    function payments(address teacher, string memory subject) external view returns (uint256);
} 