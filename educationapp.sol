// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "https://github.com/ethereum-attestation-service/eas-contracts/blob/master/contracts/IEAS.sol";
import "https://github.com/ethereum-attestation-service/eas-contracts/blob/master/contracts/ISchemaRegistry.sol";

// Import our contracts
import "./Student.sol";
import "./Teacher.sol";


contract EducationApp {
    address public owner;
    IEAS public eas;
    ISchemaRegistry public schemaRegistry;
    
    // Contract addresses
    address public teacherResolverAddress;
    address public studentResolverAddress;
    address public schoolManagementAddress;
    address public studentManagementAddress;
    
    // Schema IDs
    bytes32 public teacherSchemaId;
    bytes32 public studentSchemaId;
    
    event SchemaCreated(bytes32 schemaId, string description);
    event ContractDeployed(string contractName, address contractAddress);
    
    constructor(address _easAddress, address _schemaRegistryAddress) {
        owner = msg.sender;
        eas = IEAS(_easAddress);
        schemaRegistry = ISchemaRegistry(_schemaRegistryAddress);
    }
    
    // Create schemas for teacher and student attestations
    function createSchemas() external {
        require(msg.sender == owner, "Only owner can create schemas");
        
        // Create teacher schema
        string memory teacherSchema = "address teacher, uint256 fees, string subject";
        string memory teacherSchemaDescription = "Schema for teacher registration with subject and fees";
        teacherSchemaId = schemaRegistry.register(
            teacherSchema,
            ISchemaResolver(address(0)),
            true
        );
        emit SchemaCreated(teacherSchemaId, teacherSchemaDescription);
        
        // Create student schema
        string memory studentSchema = "address student, address teacher, uint256 validityPeriod, string subject";
        string memory studentSchemaDescription = "Schema for student enrollment with teacher, subject and validity period";
        studentSchemaId = schemaRegistry.register(
            studentSchema,
            ISchemaResolver(address(0)),
            true
        );
        emit SchemaCreated(studentSchemaId, studentSchemaDescription);
    }
    
    // Deploy all contracts
    function deployContracts() external {
        require(msg.sender == owner, "Only owner can deploy contracts");
        require(teacherSchemaId != bytes32(0) && studentSchemaId != bytes32(0), "Schemas must be created first");
        
        // Deploy TeacherResolver
        TeacherResolver teacherResolver = new TeacherResolver(eas, owner);
        teacherResolverAddress = address(teacherResolver);
        emit ContractDeployed("TeacherResolver", teacherResolverAddress);
        
        // Deploy StudentResolver
        StudentResolver studentResolver = new StudentResolver(eas, owner);
        studentResolverAddress = address(studentResolver);
        emit ContractDeployed("StudentResolver", studentResolverAddress);
        
        // Deploy SchoolManagement
        SchoolManagement schoolManagement = new SchoolManagement(address(eas));
        schoolManagementAddress = address(schoolManagement);
        schoolManagement.schemaId(teacherSchemaId);
        emit ContractDeployed("SchoolManagement", schoolManagementAddress);
        
        // Deploy StudentManagement
        StudentManagement studentManagement = new StudentManagement(address(eas));
        studentManagementAddress = address(studentManagement);
        studentManagement.setSchemaId(studentSchemaId);
        studentManagement.setTeacherResolverAddress(teacherResolverAddress);
        emit ContractDeployed("StudentManagement", studentManagementAddress);
        
        // Update schema resolvers
        schemaRegistry.register(
            "address teacher, uint256 fees, string subject",
            ISchemaResolver(teacherResolverAddress),
            true
        );
        
        schemaRegistry.register(
            "address student, address teacher, uint256 validityPeriod, string subject",
            ISchemaResolver(studentResolverAddress),
            true
        );
    }
    
    // Helper function to register a teacher
    function registerTeacher(address teacher, string calldata subject, uint256 fees) external {
        require(msg.sender == owner, "Only owner can register teachers");
        require(schoolManagementAddress != address(0), "SchoolManagement not deployed");
        
        // Encode teacher data
        bytes memory teacherData = abi.encodePacked(
            teacher,
            fees,
            bytes(subject)
        );
        
        // Call SchoolManagement to register the teacher
        SchoolManagement(schoolManagementAddress).registerTeacher(teacher, teacherData);
    }
    
    // Helper function for students to enroll in a subject
    function enrollStudent(address teacher, string calldata subject, uint256 validityPeriod) external payable {
        require(studentManagementAddress != address(0), "StudentManagement not deployed");
        
        // Call StudentManagement to enroll the student
        StudentManagement(studentManagementAddress).enrollStudent{value: msg.value}(
            msg.sender,
            teacher,
            subject,
            validityPeriod
        );
    }
    
    // Helper function to check if a student's enrollment is valid
    function isEnrollmentValid(address student, address teacher, string calldata subject) external view returns (bool) {
        require(studentManagementAddress != address(0), "StudentManagement not deployed");
        
        return StudentManagement(studentManagementAddress).isEnrollmentValid(student, teacher, subject);
    }
    
    // Helper function to get remaining validity period
    function getRemainingValidity(address student, address teacher, string calldata subject) external view returns (uint256) {
        require(studentManagementAddress != address(0), "StudentManagement not deployed");
        
        return StudentManagement(studentManagementAddress).getRemainingValidity(student, teacher, subject);
    }
    
    // Helper function to revoke expired enrollments
    function revokeExpiredEnrollments(address student) external {
        require(studentManagementAddress != address(0), "StudentManagement not deployed");
        
        StudentManagement(studentManagementAddress).revokeExpiredEnrollments(student);
    }
} 