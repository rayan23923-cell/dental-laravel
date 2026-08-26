-- phpMyAdmin SQL Dump
-- version 5.2.2
-- https://www.phpmyadmin.net/
--
-- Host: localhost:3306
-- Generation Time: Aug 18, 2026 at 02:42 PM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `clinic_system2`
--

-- --------------------------------------------------------

--
-- Table structure for table `academic_sessions`
--

CREATE TABLE `academic_sessions` (
  `id` int(11) NOT NULL,
  `name` varchar(150) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `is_current` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



-- --------------------------------------------------------

--
-- Table structure for table `appointments`
--

CREATE TABLE `appointments` (
  `id` int(11) NOT NULL,
  `full_name` varchar(250) NOT NULL,
  `patient_id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `task_id` int(11) NOT NULL,
  `appointment_date` date NOT NULL,
  `confirmed_by_accountant` tinyint(1) DEFAULT 0,
  `pinned` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `app_settings`
--

CREATE TABLE `app_settings` (
  `id` int(11) NOT NULL,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `case_sheet_types`
--

CREATE TABLE `case_sheet_types` (
  `id` int(11) NOT NULL,
  `type_code` varchar(50) NOT NULL,
  `name_ar` varchar(100) NOT NULL,
  `name_en` varchar(100) NOT NULL,
  `icon` varchar(50) NOT NULL DEFAULT 'file-medical',
  `color` varchar(20) NOT NULL DEFAULT 'secondary',
  `page_url` varchar(255) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `display_order` int(11) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `clinics`
--

CREATE TABLE `clinics` (
  `id` int(11) NOT NULL,
  `phase_id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `clinic_settings`
--

CREATE TABLE `clinic_settings` (
  `id` int(11) NOT NULL,
  `clinic_name` varchar(255) DEFAULT 'عيادة الأسنان',
  `clinic_description` text DEFAULT NULL,
  `clinic_logo` varchar(255) DEFAULT 'default-logo.png',
  `clinic_address` text DEFAULT NULL,
  `clinic_phone` varchar(50) DEFAULT NULL,
  `clinic_email` varchar(255) DEFAULT NULL,
  `clinic_website` varchar(255) DEFAULT NULL,
  `clinic_working_hours` text DEFAULT NULL,
  `clinic_currency` varchar(50) DEFAULT 'ريال',
  `clinic_timezone` varchar(64) DEFAULT 'Asia/Riyadh',
  `base_url` varchar(255) DEFAULT '/dental_clinic',
  `enable_notifications` tinyint(1) DEFAULT 1,
  `enable_sms` tinyint(1) DEFAULT 0,
  `enable_email` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `university_name` varchar(255) DEFAULT 'University of Baghdad',
  `college_name` varchar(255) DEFAULT 'College of Dentistry',
  `university_logo` varchar(255) DEFAULT NULL,
  `mikrotik_ip` varchar(50) DEFAULT '192.168.88.1',
  `mikrotik_user` varchar(50) DEFAULT 'admin',
  `mikrotik_pass` varchar(255) DEFAULT '',
  `mikrotik_ssh_port` int(11) DEFAULT 22,
  `jwt_secret_key` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `complete_denture_records`
--

CREATE TABLE `complete_denture_records` (
  `id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `task_instances_id` int(11) DEFAULT NULL,
  `student_name` varchar(255) DEFAULT NULL,
  `patient_name` varchar(255) DEFAULT NULL,
  `group_name` varchar(100) DEFAULT NULL,
  `age` int(11) DEFAULT NULL,
  `sex` varchar(50) DEFAULT NULL,
  `telephone` varchar(50) DEFAULT NULL,
  `occupation` varchar(255) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `first_time` varchar(10) DEFAULT NULL,
  `medical_history` text DEFAULT NULL,
  `dental_extraction_reason` text DEFAULT NULL,
  `dentist_visit_regular` varchar(255) DEFAULT NULL,
  `last_tooth_extracted` varchar(255) DEFAULT NULL,
  `last_tooth_extracted_teeth` varchar(255) DEFAULT NULL,
  `complete_denture_reason` text DEFAULT NULL,
  `partial_denture_reason` text DEFAULT NULL,
  `previous_complete_denture` text DEFAULT NULL,
  `previous_partial_denture` text DEFAULT NULL,
  `not_using_reason` text DEFAULT NULL,
  `new_denture_reason` text DEFAULT NULL,
  `old_denture_retention` varchar(255) DEFAULT NULL,
  `old_denture_stability` varchar(255) DEFAULT NULL,
  `old_denture_centric` varchar(255) DEFAULT NULL,
  `old_denture_vertical` varchar(255) DEFAULT NULL,
  `old_denture_appearance` varchar(255) DEFAULT NULL,
  `old_denture_comfort` varchar(255) DEFAULT NULL,
  `facial_muscle_tone` varchar(255) DEFAULT NULL,
  `face_form` varchar(255) DEFAULT NULL,
  `angles_jaw_classification` varchar(255) DEFAULT NULL,
  `vertical_dimensions_rest` varchar(255) DEFAULT NULL,
  `ridge_form_upper` varchar(255) DEFAULT NULL,
  `ridge_form_lower` varchar(255) DEFAULT NULL,
  `mucosa_upper` varchar(255) DEFAULT NULL,
  `mucosa_lower` varchar(255) DEFAULT NULL,
  `palate_depth` varchar(255) DEFAULT NULL,
  `tongue_size` varchar(255) DEFAULT NULL,
  `bony_exostosis` varchar(255) DEFAULT NULL,
  `teeth_to_extract` varchar(255) DEFAULT NULL,
  `tmj_disorder` varchar(255) DEFAULT NULL,
  `muscles_mastication` varchar(255) DEFAULT NULL,
  `facial_tissue` varchar(255) DEFAULT NULL,
  `missing_teeth` varchar(255) DEFAULT NULL,
  `soft_tissue_condition` varchar(255) DEFAULT NULL,
  `abnormal_lesion` varchar(255) DEFAULT NULL,
  `abutments_mobility` varchar(255) DEFAULT NULL,
  `preprosthetic_treatment` text DEFAULT NULL,
  `diagnosis_starting` text DEFAULT NULL,
  `diagnosis_instructor_signature` text DEFAULT NULL,
  `stage_preliminary_signature` text DEFAULT NULL,
  `stage_preliminary_date` date DEFAULT NULL,
  `stage_preliminary_grade` varchar(50) DEFAULT NULL,
  `stage_surveying_signature` text DEFAULT NULL,
  `stage_surveying_date` date DEFAULT NULL,
  `stage_surveying_grade` varchar(50) DEFAULT NULL,
  `stage_final_signature` text DEFAULT NULL,
  `stage_final_date` date DEFAULT NULL,
  `stage_final_grade` varchar(50) DEFAULT NULL,
  `stage_jawrel_signature` text DEFAULT NULL,
  `stage_jawrel_date` date DEFAULT NULL,
  `stage_jawrel_grade` varchar(50) DEFAULT NULL,
  `stage_trial_signature` text DEFAULT NULL,
  `stage_trial_date` date DEFAULT NULL,
  `stage_trial_grade` varchar(50) DEFAULT NULL,
  `stage_flasking_signature` text DEFAULT NULL,
  `stage_flasking_date` date DEFAULT NULL,
  `stage_flasking_grade` varchar(50) DEFAULT NULL,
  `stage_cd_signature` text DEFAULT NULL,
  `stage_cd_date` date DEFAULT NULL,
  `stage_cd_grade` varchar(50) DEFAULT NULL,
  `stage_adjust1_signature` text DEFAULT NULL,
  `stage_adjust1_date` date DEFAULT NULL,
  `stage_adjust1_grade` varchar(50) DEFAULT NULL,
  `stage_finaleval_signature` text DEFAULT NULL,
  `stage_finaleval_date` date DEFAULT NULL,
  `stage_finaleval_grade` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



-- --------------------------------------------------------

--
-- Table structure for table `dental_charts`
--

CREATE TABLE `dental_charts` (
  `id` int(11) NOT NULL,
  `patient_id` varchar(255) NOT NULL COMMENT 'Patient name',
  `patient_phone` varchar(50) DEFAULT NULL COMMENT 'Patient phone number',
  `patient_age` int(11) DEFAULT NULL COMMENT 'Patient age',
  `patient_sex` varchar(20) DEFAULT NULL COMMENT 'Patient sex',
  `patient_address` varchar(255) DEFAULT NULL COMMENT 'Patient address',
  `patient_occupation` varchar(255) DEFAULT NULL COMMENT 'Patient occupation',
  `doctor_id` int(11) NOT NULL,
  `task_instances_id` int(11) DEFAULT NULL,
  `chart_type` enum('primary','permanent') NOT NULL DEFAULT 'permanent',
  `visit_date` datetime NOT NULL DEFAULT current_timestamp(),
  `notes` text DEFAULT NULL,
  `endodontics_data` longtext DEFAULT NULL COMMENT 'Endodontics data stored as JSON',
  `chief_complaint` text DEFAULT NULL,
  `history_of_complaint` text DEFAULT NULL,
  `oral_hygiene` text DEFAULT NULL,
  `periodontal_condition` text DEFAULT NULL,
  `non_vital_teeth` text DEFAULT NULL COMMENT 'Non-vital teeth list',
  `missing_teeth` text DEFAULT NULL COMMENT 'Missing teeth list',
  `crown_bridge_teeth` text DEFAULT NULL COMMENT 'Crown & Bridge teeth list',
  `tooth_data` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `treatment_plan_date` date DEFAULT NULL,
  `treatment_plan_notes` text DEFAULT NULL,
  `senior_doctor_name` varchar(255) DEFAULT NULL,
  `senior_signature` longtext DEFAULT NULL,
  `chart_snapshot` longtext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `dental_follow_ups`
--

CREATE TABLE `dental_follow_ups` (
  `id` int(11) NOT NULL,
  `dental_chart_id` int(11) NOT NULL,
  `follow_up_date` datetime NOT NULL,
  `follow_up_type` enum('checkup','treatment_continuation','post_treatment','emergency') NOT NULL,
  `status` enum('scheduled','completed','cancelled','rescheduled') DEFAULT 'scheduled',
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `departments`
--

CREATE TABLE `departments` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `stage_id` int(11) DEFAULT NULL,
  `education_type_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `department_permissions`
--

CREATE TABLE `department_permissions` (
  `id` int(11) NOT NULL,
  `role_assignment_id` int(11) NOT NULL,
  `permission_type` varchar(50) NOT NULL COMMENT 'view, edit, approve, manage_users, etc.',
  `granted` tinyint(1) DEFAULT 1,
  `created_at` datetime DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `department_role_activity_log`
--

CREATE TABLE `department_role_activity_log` (
  `id` int(11) NOT NULL,
  `role_assignment_id` int(11) NOT NULL,
  `action` varchar(100) NOT NULL COMMENT 'assigned, removed, updated, etc.',
  `performed_by` int(11) NOT NULL,
  `details` text DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



-- --------------------------------------------------------

--
-- Table structure for table `department_role_assignments`
--

CREATE TABLE `department_role_assignments` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `department_id` int(11) NOT NULL,
  `stage_id` int(11) NOT NULL,
  `role_type` enum('senior','hr') NOT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `assigned_by` int(11) DEFAULT NULL,
  `assigned_at` datetime DEFAULT current_timestamp(),
  `status` enum('active','inactive') DEFAULT 'active',
  `notes` text DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



-- --------------------------------------------------------

--
-- Table structure for table `doctors`
--

CREATE TABLE `doctors` (
  `id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `username` varchar(100) NOT NULL,
  `password` varchar(255) NOT NULL,
  `phone` varchar(50) DEFAULT NULL,
  `education_type_id` int(11) NOT NULL,
  `stage_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `profile_image` varchar(255) DEFAULT NULL,
  `email` varchar(250) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



-- --------------------------------------------------------

--
-- Table structure for table `doctor_group_members`
--

CREATE TABLE `doctor_group_members` (
  `id` int(11) NOT NULL,
  `group_id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `added_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `doctor_tasks`
--

CREATE TABLE `doctor_tasks` (
  `id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `task_id` int(11) NOT NULL,
  `academic_session_id` int(11) DEFAULT NULL,
  `completed` tinyint(1) DEFAULT 0,
  `completed_at` datetime DEFAULT NULL,
  `target` int(11) DEFAULT 0,
  `status` enum('منجزة','غير منجزة') DEFAULT 'غير منجزة'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `doctor_task_progress`
--

CREATE TABLE `doctor_task_progress` (
  `id` int(11) NOT NULL,
  `task_id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `assigned_date` datetime NOT NULL DEFAULT current_timestamp(),
  `completion_date` datetime DEFAULT NULL,
  `status` enum('assigned','completed') NOT NULL DEFAULT 'assigned',
  `notes` text DEFAULT NULL,
  `assigned_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `marked_done_by_admin` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `education_types`
--

CREATE TABLE `education_types` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `endodontics_images`
--

CREATE TABLE `endodontics_images` (
  `id` int(11) NOT NULL,
  `dental_chart_id` int(11) NOT NULL,
  `visit_type` varchar(50) NOT NULL,
  `image_data` longblob DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `groups`
--

CREATE TABLE `groups` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `stage_id` int(11) NOT NULL,
  `academic_session_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `group_slots`
--

CREATE TABLE `group_slots` (
  `id` int(11) NOT NULL,
  `group_id` int(11) NOT NULL,
  `day` varchar(20) NOT NULL,
  `start_time` time NOT NULL,
  `end_time` time NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `mikrotik_settings`
--

CREATE TABLE `mikrotik_settings` (
  `id` int(11) NOT NULL,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `oral_medicine_charts`
--

CREATE TABLE `oral_medicine_charts` (
  `id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `task_instances_id` int(11) DEFAULT NULL,
  `case_no` varchar(50) DEFAULT NULL,
  `visit_date` date DEFAULT NULL,
  `patient_id` varchar(255) DEFAULT NULL COMMENT 'Patient name',
  `patient_age` int(11) DEFAULT NULL,
  `patient_sex` varchar(20) DEFAULT NULL,
  `patient_address` text DEFAULT NULL,
  `patient_occupation` varchar(255) DEFAULT NULL,
  `patient_phone` varchar(50) DEFAULT NULL,
  `chief_complaint` text DEFAULT NULL,
  `past_medical_history` text DEFAULT NULL COMMENT 'JSON encoded PMH data',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `surgical_history` text DEFAULT NULL COMMENT 'JSON encoded surgical history data',
  `family_history` text DEFAULT NULL COMMENT 'JSON encoded family history data',
  `social_history` text DEFAULT NULL COMMENT 'JSON encoded social history data',
  `clinical_examination` text DEFAULT NULL COMMENT 'JSON encoded clinical examination and pain pattern data',
  `extraoral_intraoral_examination` text DEFAULT NULL COMMENT 'JSON encoded extraoral/intraoral examination data',
  `present_teeth` text DEFAULT NULL COMMENT 'JSON encoded present teeth data',
  `teeth_requiring_treatment` text DEFAULT NULL COMMENT 'JSON encoded teeth requiring treatment data',
  `jaws_teeth_relations` text DEFAULT NULL COMMENT 'JSON encoded jaws and teeth relations data',
  `history_of_complaint` text DEFAULT NULL COMMENT 'JSON encoded history of complaint data',
  `investigations_diagnosis` text DEFAULT NULL COMMENT 'JSON encoded investigations, diagnosis, and treatment plan',
  `student_visits` text DEFAULT NULL COMMENT 'JSON encoded student information and follow-up visits'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `orthodontics_records`
--

CREATE TABLE `orthodontics_records` (
  `id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `task_instances_id` int(11) DEFAULT NULL,
  `student_name` varchar(255) DEFAULT NULL,
  `group_name` varchar(100) DEFAULT NULL,
  `supervised_by` varchar(255) DEFAULT NULL,
  `patient_name` varchar(255) NOT NULL,
  `patient_age` int(11) DEFAULT NULL,
  `patient_sex` varchar(20) DEFAULT NULL,
  `patient_address` text DEFAULT NULL,
  `patient_phone` varchar(50) DEFAULT NULL,
  `referral_date` date DEFAULT NULL,
  `referred_from` varchar(255) DEFAULT NULL,
  `examination_data` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `patients`
--

CREATE TABLE `patients` (
  `id` int(11) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `task_id` int(11) DEFAULT NULL,
  `stage_id` int(11) DEFAULT NULL,
  `group_id` int(11) DEFAULT NULL,
  `doctor_id` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `patients_admin`
--

CREATE TABLE `patients_admin` (
  `id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `phone` varchar(20) NOT NULL,
  `days` text NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `patients_simple`
--

CREATE TABLE `patients_simple` (
  `id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `phone` varchar(20) NOT NULL,
  `age` int(11) DEFAULT NULL,
  `sex` enum('male','female') DEFAULT NULL,
  `address` varchar(255) DEFAULT NULL,
  `occupation` varchar(100) DEFAULT NULL,
  `note` text DEFAULT NULL,
  `day` varchar(50) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `gender` varchar(10) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `payments`
--

CREATE TABLE `payments` (
  `id` int(11) NOT NULL,
  `appointment_id` int(11) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `paid_by` varchar(100) DEFAULT NULL,
  `paid_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `periodontal_charts`
--

CREATE TABLE `periodontal_charts` (
  `id` int(11) NOT NULL,
  `task_instances_id` int(11) DEFAULT NULL COMMENT 'Link to task instance',
  `patient_id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `student_name` varchar(255) DEFAULT NULL,
  `student_group` varchar(100) DEFAULT NULL,
  `case_start_date` date DEFAULT NULL,
  `mentor_name` varchar(255) DEFAULT NULL,
  `patient_name` varchar(255) DEFAULT NULL,
  `patient_first_name` varchar(255) DEFAULT NULL,
  `patient_middle_name` varchar(255) DEFAULT NULL,
  `patient_surname` varchar(255) DEFAULT NULL,
  `patient_dob` date DEFAULT NULL,
  `patient_marital_status` varchar(50) DEFAULT NULL,
  `chart_date` date NOT NULL,
  `chief_complaints` text DEFAULT NULL,
  `history_present_illness` text DEFAULT NULL,
  `med_general_health` text DEFAULT NULL,
  `med_hospitalization` varchar(10) DEFAULT NULL,
  `med_hospitalization_reason` text DEFAULT NULL,
  `med_medication` text DEFAULT NULL,
  `med_others_disease` varchar(10) DEFAULT 'no',
  `med_osteoporosis` varchar(10) DEFAULT 'no',
  `med_malignancies` varchar(10) DEFAULT 'no',
  `med_git` varchar(10) DEFAULT 'no',
  `med_respiratory` varchar(10) DEFAULT 'no',
  `med_asthma` varchar(10) DEFAULT 'no',
  `med_epilepsy` varchar(10) DEFAULT 'no',
  `med_urinary` varchar(10) DEFAULT 'no',
  `med_skin_dis` varchar(10) DEFAULT 'no',
  `med_cva` varchar(10) DEFAULT 'no',
  `med_hiv` varchar(10) DEFAULT 'no',
  `med_diabetes` varchar(10) DEFAULT 'no',
  `med_hepatitis` varchar(10) DEFAULT 'no',
  `med_blood_pressure` varchar(10) DEFAULT 'no',
  `med_blood_dis` varchar(10) DEFAULT 'no',
  `med_heart_surgery` varchar(10) DEFAULT 'no',
  `med_disease_notes` text DEFAULT NULL,
  `med_allergy_others` varchar(10) DEFAULT 'no',
  `med_allergy_food` varchar(10) DEFAULT 'no',
  `med_allergy_antibiotics` varchar(10) DEFAULT 'no',
  `med_allergy_aspirin` varchar(10) DEFAULT 'no',
  `med_allergy_local_anest` varchar(10) DEFAULT 'no',
  `med_allergy_notes` text DEFAULT NULL,
  `med_women_pregnancy` varchar(10) DEFAULT NULL,
  `med_women_weeks` varchar(50) DEFAULT NULL,
  `med_women_pills` varchar(10) DEFAULT NULL,
  `med_women_nursing` varchar(10) DEFAULT NULL,
  `med_other_conditions` text DEFAULT NULL,
  `dental_last_visit_date` date DEFAULT NULL,
  `dental_last_visit_reason` text DEFAULT NULL,
  `dental_complications` text DEFAULT NULL,
  `dental_prev_perio_treatment` varchar(10) DEFAULT NULL,
  `dental_prev_perio_when` varchar(255) DEFAULT NULL,
  `dental_prev_perio_for` varchar(255) DEFAULT NULL,
  `oral_chemical_agent` varchar(10) DEFAULT NULL,
  `family_systemic_disease` varchar(10) DEFAULT NULL,
  `family_systemic_disease_details` text DEFAULT NULL,
  `hist_smoker` varchar(10) DEFAULT 'no',
  `hist_smoker_previous` tinyint(1) DEFAULT 0,
  `hist_smoker_when_stopped` varchar(255) DEFAULT NULL,
  `hist_smoker_type` varchar(255) DEFAULT NULL,
  `hist_smoker_frequency` varchar(255) DEFAULT NULL,
  `hist_smoker_duration` varchar(255) DEFAULT NULL,
  `alcohol_consumption` varchar(10) DEFAULT NULL,
  `behavioural_habits` text DEFAULT NULL,
  `dietary_habit` text DEFAULT NULL,
  `hist_diabetes` varchar(10) DEFAULT 'no',
  `hist_diabetes_controlled` varchar(10) DEFAULT NULL,
  `hist_diabetes_lab` text DEFAULT NULL,
  `hist_brushing_freq` varchar(20) DEFAULT 'twice',
  `hist_brush_type` varchar(20) DEFAULT 'manual',
  `hist_brushing_duration` varchar(50) DEFAULT NULL,
  `hist_interproximal` varchar(10) DEFAULT 'no',
  `hist_interproximal_details` text DEFAULT NULL,
  `hist_family_perio` varchar(10) DEFAULT 'no',
  `hist_family_perio_details` text DEFAULT NULL,
  `hist_previous_treatment` text DEFAULT NULL,
  `exam_tmj_click` varchar(10) DEFAULT 'no',
  `exam_facial_asymmetry` varchar(10) DEFAULT 'no',
  `exam_facial_asymmetry_details` text DEFAULT NULL,
  `exam_missing_teeth` int(11) DEFAULT 0,
  `exam_soft_tissue` varchar(10) DEFAULT 'no',
  `exam_soft_tissue_comments` text DEFAULT NULL,
  `exam_occlusal_trauma` varchar(10) DEFAULT 'no',
  `exam_occlusal_trauma_details` text DEFAULT NULL,
  `exam_mobile_teeth` varchar(10) DEFAULT 'no',
  `exam_mobile_teeth_which` text DEFAULT NULL,
  `exam_caries` varchar(10) DEFAULT 'no',
  `exam_caries_teeth` text DEFAULT NULL,
  `exam_bpe_ur` varchar(10) DEFAULT NULL,
  `exam_bpe_ua` varchar(10) DEFAULT NULL,
  `exam_bpe_ul` varchar(10) DEFAULT NULL,
  `exam_bpe_lr` varchar(10) DEFAULT NULL,
  `exam_bpe_la` varchar(10) DEFAULT NULL,
  `exam_bpe_ll` varchar(10) DEFAULT NULL,
  `exam_radiograph_periapical` tinyint(1) DEFAULT 0,
  `exam_radiograph_bitewing` tinyint(1) DEFAULT 0,
  `exam_radiograph_panoramic` tinyint(1) DEFAULT 0,
  `exam_radiograph_cbct` tinyint(1) DEFAULT 0,
  `exam_other_investigations` text DEFAULT NULL,
  `oral_hygiene` text DEFAULT NULL,
  `periodontal_condition` text DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `diagnosis_pattern` varchar(255) DEFAULT NULL,
  `diagnosis_stage` varchar(50) DEFAULT NULL,
  `diagnosis_grade` varchar(50) DEFAULT NULL,
  `diagnosis_status` varchar(50) DEFAULT NULL,
  `diagnosis_risk_factors` text DEFAULT NULL,
  `img_chief_complaint` text DEFAULT NULL,
  `img_medical_history` text DEFAULT NULL,
  `img_smoker_yes` tinyint(1) DEFAULT 0,
  `img_smoker_no` tinyint(1) DEFAULT 0,
  `img_smoker_prev` tinyint(1) DEFAULT 0,
  `img_smoker_stopped` varchar(255) DEFAULT NULL,
  `img_diabetes_yes` tinyint(1) DEFAULT 0,
  `img_diabetes_no` tinyint(1) DEFAULT 0,
  `img_diabetes_controlled_yes` tinyint(1) DEFAULT 0,
  `img_diabetes_controlled_no` tinyint(1) DEFAULT 0,
  `img_diabetes_lab` varchar(255) DEFAULT NULL,
  `img_brushing_once` tinyint(1) DEFAULT 0,
  `img_brushing_twice` tinyint(1) DEFAULT 0,
  `img_brushing_three` tinyint(1) DEFAULT 0,
  `img_brushing_manual` tinyint(1) DEFAULT 0,
  `img_brushing_powered` tinyint(1) DEFAULT 0,
  `img_interproximal_yes` tinyint(1) DEFAULT 0,
  `img_interproximal_no` tinyint(1) DEFAULT 0,
  `img_interproximal_type` varchar(255) DEFAULT NULL,
  `img_fam_hist_yes` tinyint(1) DEFAULT 0,
  `img_fam_hist_no` tinyint(1) DEFAULT 0,
  `img_fam_hist_details` text DEFAULT NULL,
  `img_prev_treatment` text DEFAULT NULL,
  `img_tmj_yes` tinyint(1) DEFAULT 0,
  `img_tmj_no` tinyint(1) DEFAULT 0,
  `img_facial_yes` tinyint(1) DEFAULT 0,
  `img_facial_no` tinyint(1) DEFAULT 0,
  `img_facial_details` text DEFAULT NULL,
  `img_missing_teeth` varchar(255) DEFAULT NULL,
  `img_soft_tissue_yes` tinyint(1) DEFAULT 0,
  `img_soft_tissue_no` tinyint(1) DEFAULT 0,
  `img_soft_tissue_comments` text DEFAULT NULL,
  `img_occlusal_yes` tinyint(1) DEFAULT 0,
  `img_occlusal_no` tinyint(1) DEFAULT 0,
  `img_mobile_yes` tinyint(1) DEFAULT 0,
  `img_mobile_no` tinyint(1) DEFAULT 0,
  `img_mobile_teeth` varchar(255) DEFAULT NULL,
  `img_caries_yes` tinyint(1) DEFAULT 0,
  `img_caries_no` tinyint(1) DEFAULT 0,
  `img_caries_teeth` varchar(255) DEFAULT NULL,
  `women_pregnancy` varchar(10) DEFAULT NULL,
  `pregnancy_weeks` varchar(50) DEFAULT NULL,
  `women_birth_control` varchar(10) DEFAULT NULL,
  `women_nursing` varchar(10) DEFAULT NULL,
  `clinical_notes` text DEFAULT NULL,
  `treatment_plan` text DEFAULT NULL,
  `treatment_plan_date` date DEFAULT NULL,
  `senior_doctor_name` varchar(255) DEFAULT NULL,
  `approval_date` date DEFAULT NULL,
  `senior_signature` longtext DEFAULT NULL,
  `chart_data` longtext NOT NULL COMMENT 'JSON data containing all measurements',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `patient_phone` varchar(50) DEFAULT NULL COMMENT 'Patient phone number',
  `patient_age` int(11) DEFAULT NULL,
  `patient_gender` varchar(10) DEFAULT NULL,
  `patient_address` text DEFAULT NULL,
  `patient_occupation` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Periodontal charting data';



-- --------------------------------------------------------

--
-- Table structure for table `permissions`
--

CREATE TABLE `permissions` (
  `id` int(11) NOT NULL,
  `role_id` int(11) NOT NULL,
  `page` varchar(100) NOT NULL,
  `can_view` tinyint(1) NOT NULL DEFAULT 0,
  `can_edit` tinyint(1) NOT NULL DEFAULT 0,
  `can_full_control` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `phases`
--

CREATE TABLE `phases` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `prevention_records`
--

CREATE TABLE `prevention_records` (
  `id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `task_instances_id` int(11) DEFAULT NULL,
  `patient_data` text DEFAULT NULL,
  `examination_data` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `prosthodontics_records`
--

CREATE TABLE `prosthodontics_records` (
  `id` int(11) NOT NULL,
  `task_instances_id` int(11) DEFAULT NULL COMMENT 'Link to task instance',
  `doctor_id` int(11) NOT NULL,
  `student_name` varchar(255) DEFAULT NULL,
  `patient_name` varchar(255) DEFAULT NULL,
  `patient_phone` varchar(50) DEFAULT NULL COMMENT 'Patient phone number',
  `group_name` varchar(100) DEFAULT NULL,
  `age` int(11) DEFAULT NULL,
  `sex` varchar(50) DEFAULT NULL,
  `telephone` varchar(50) DEFAULT NULL,
  `occupation` varchar(255) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `first_time` varchar(10) DEFAULT NULL,
  `medical_history` text DEFAULT NULL,
  `dental_extraction_reason` text DEFAULT NULL,
  `dentist_visit_regular` text DEFAULT NULL,
  `partial_denture_reason` text DEFAULT NULL,
  `previous_partial_denture` text DEFAULT NULL,
  `not_using_reason` text DEFAULT NULL,
  `tmj_disorder` varchar(50) DEFAULT NULL,
  `muscles_mastication` varchar(100) DEFAULT NULL,
  `facial_tissue` varchar(255) DEFAULT NULL,
  `missing_teeth` text DEFAULT NULL,
  `caries_teeth` text DEFAULT NULL,
  `soft_tissue_condition` text DEFAULT NULL,
  `abnormal_lesion` text DEFAULT NULL,
  `abutments_mobility` text DEFAULT NULL,
  `teeth_extraction` text DEFAULT NULL,
  `preprosthetic_treatment` text DEFAULT NULL,
  `diagnosis_starting` text DEFAULT NULL,
  `diagnosis_instructor_signature` text DEFAULT NULL,
  `diagnosis_date` date DEFAULT NULL,
  `diagnosis_grade` varchar(50) DEFAULT NULL,
  `stage_preliminary_signature` text DEFAULT NULL,
  `stage_preliminary_date` date DEFAULT NULL,
  `stage_preliminary_grade` varchar(50) DEFAULT NULL,
  `stage_surveying_signature` text DEFAULT NULL,
  `stage_surveying_date` date DEFAULT NULL,
  `stage_surveying_grade` varchar(50) DEFAULT NULL,
  `stage_final_signature` text DEFAULT NULL,
  `stage_final_date` date DEFAULT NULL,
  `stage_final_grade` varchar(50) DEFAULT NULL,
  `stage_jawrel_signature` text DEFAULT NULL,
  `stage_jawrel_date` date DEFAULT NULL,
  `stage_jawrel_grade` varchar(50) DEFAULT NULL,
  `stage_trial_signature` text DEFAULT NULL,
  `stage_trial_date` date DEFAULT NULL,
  `stage_trial_grade` varchar(50) DEFAULT NULL,
  `stage_flasking_signature` text DEFAULT NULL,
  `stage_flasking_date` date DEFAULT NULL,
  `stage_flasking_grade` varchar(50) DEFAULT NULL,
  `stage_rpd_signature` text DEFAULT NULL,
  `stage_rpd_date` date DEFAULT NULL,
  `stage_rpd_grade` varchar(50) DEFAULT NULL,
  `stage_adjust1_signature` text DEFAULT NULL,
  `stage_adjust1_date` date DEFAULT NULL,
  `stage_adjust1_grade` varchar(50) DEFAULT NULL,
  `stage_finaleval_signature` text DEFAULT NULL,
  `stage_finaleval_date` date DEFAULT NULL,
  `stage_finaleval_grade` varchar(50) DEFAULT NULL,
  `tooth_chart_data` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `register_days`
--

CREATE TABLE `register_days` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `sort_order` int(11) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `register_day_service`
--

CREATE TABLE `register_day_service` (
  `day_id` int(11) NOT NULL,
  `service_name` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `register_day_service_map`
--

CREATE TABLE `register_day_service_map` (
  `day_id` int(11) NOT NULL,
  `service_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `register_services`
--

CREATE TABLE `register_services` (
  `id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `roles`
--

CREATE TABLE `roles` (
  `id` int(11) NOT NULL,
  `name` varchar(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `role_permissions`
--

CREATE TABLE `role_permissions` (
  `id` int(11) NOT NULL,
  `role_id` int(11) NOT NULL,
  `permission_id` int(11) NOT NULL,
  `can_view` tinyint(1) DEFAULT 0,
  `can_edit` tinyint(1) DEFAULT 0,
  `can_delete` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `role_stage_department_permissions`
--

CREATE TABLE `role_stage_department_permissions` (
  `id` int(11) NOT NULL,
  `role_id` int(11) NOT NULL,
  `stage_id` int(11) NOT NULL,
  `department_id` int(11) NOT NULL,
  `can_view` tinyint(1) DEFAULT 0,
  `can_create` tinyint(1) DEFAULT 0,
  `can_edit` tinyint(1) DEFAULT 0,
  `can_delete` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `stages`
--

CREATE TABLE `stages` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `education_type_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `surgeries`
--

CREATE TABLE `surgeries` (
  `id` int(11) NOT NULL,
  `task_instances_id` int(11) DEFAULT NULL COMMENT 'Link to task instance',
  `patient_id` int(11) NOT NULL,
  `patient_name` varchar(255) DEFAULT NULL,
  `doctor_id` int(11) NOT NULL,
  `student_name` varchar(255) DEFAULT NULL,
  `grade_group` varchar(50) DEFAULT NULL,
  `surgery_date` datetime DEFAULT current_timestamp(),
  `surgery_date_field` date DEFAULT NULL,
  `start_time` time DEFAULT NULL,
  `staff_signature` varchar(255) DEFAULT NULL,
  `surgery_type` varchar(100) DEFAULT NULL,
  `chief_complaint` text DEFAULT NULL,
  `cc_pain` tinyint(1) DEFAULT 0,
  `cc_swelling` tinyint(1) DEFAULT 0,
  `cc_others` varchar(255) DEFAULT NULL,
  `medical_history` text DEFAULT NULL,
  `hpi_duration` text DEFAULT NULL,
  `hpi_onset` text DEFAULT NULL,
  `hpi_factors` text DEFAULT NULL,
  `hpi_characteristics` text DEFAULT NULL,
  `past_dental_history` text DEFAULT NULL,
  `mh_blood_pressure` varchar(10) DEFAULT 'no',
  `mh_diabetes` varchar(10) DEFAULT 'no',
  `mh_heart` varchar(10) DEFAULT 'no',
  `mh_thyroid` varchar(10) DEFAULT 'no',
  `mh_bleeding` varchar(10) DEFAULT 'no',
  `mh_epilepsy` varchar(10) DEFAULT 'no',
  `mh_respiratory` varchar(10) DEFAULT 'no',
  `mh_git` varchar(10) DEFAULT 'no',
  `mh_liver` varchar(10) DEFAULT 'no',
  `mh_kidney` varchar(10) DEFAULT 'no',
  `mh_hiv` varchar(10) DEFAULT 'no',
  `mh_implants` varchar(10) DEFAULT 'no',
  `mh_hospitalization` varchar(10) DEFAULT 'no',
  `mh_hospitalization_details` text DEFAULT NULL,
  `mh_smoking` varchar(10) DEFAULT 'no',
  `mh_smoking_amount` varchar(255) DEFAULT NULL,
  `mh_allergies` varchar(10) DEFAULT 'no',
  `mh_allergies_details` text DEFAULT NULL,
  `mh_drugs` varchar(10) DEFAULT 'no',
  `mh_drugs_details` text DEFAULT NULL,
  `mh_pregnant` varchar(10) DEFAULT 'no',
  `exam_extraoral` text DEFAULT NULL,
  `exam_intraoral` text DEFAULT NULL,
  `investigation` text DEFAULT NULL,
  `diagnosis` text DEFAULT NULL,
  `treatment_tooth` varchar(100) DEFAULT NULL,
  `selected_teeth` text DEFAULT NULL,
  `surgical_procedure` text DEFAULT NULL,
  `anesthesia_type` varchar(50) DEFAULT NULL,
  `duration_minutes` int(11) DEFAULT NULL,
  `complications` text DEFAULT NULL,
  `postop_instructions` text DEFAULT NULL,
  `follow_up_date` date DEFAULT NULL,
  `status` enum('planned','in_progress','completed','cancelled') DEFAULT 'planned',
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `patient_phone` varchar(50) DEFAULT NULL COMMENT 'Patient phone number',
  `patient_age` int(11) DEFAULT NULL,
  `patient_gender` varchar(10) DEFAULT NULL,
  `patient_address` text DEFAULT NULL,
  `patient_occupation` varchar(255) DEFAULT NULL,
  `senior_doctor_name` varchar(255) DEFAULT NULL,
  `approval_date` date DEFAULT NULL,
  `senior_signature` longtext DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `surgery_follow_ups`
--

CREATE TABLE `surgery_follow_ups` (
  `id` int(11) NOT NULL,
  `surgery_id` int(11) NOT NULL,
  `follow_up_date` date NOT NULL,
  `findings` text DEFAULT NULL,
  `patient_status` varchar(100) DEFAULT NULL,
  `next_appointment` date DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `surgery_images`
--

CREATE TABLE `surgery_images` (
  `id` int(11) NOT NULL,
  `surgery_id` int(11) NOT NULL,
  `image_path` varchar(255) NOT NULL,
  `image_type` enum('preop','intraop','postop') DEFAULT 'intraop',
  `description` text DEFAULT NULL,
  `uploaded_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `surgery_medications`
--

CREATE TABLE `surgery_medications` (
  `id` int(11) NOT NULL,
  `surgery_id` int(11) NOT NULL,
  `medication_name` varchar(255) NOT NULL,
  `dosage` varchar(100) DEFAULT NULL,
  `frequency` varchar(100) DEFAULT NULL,
  `duration` varchar(100) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `tasks`
--

CREATE TABLE `tasks` (
  `id` int(11) NOT NULL,
  `department_id` int(11) NOT NULL,
  `case_sheet_type_id` int(11) NOT NULL,
  `stage_id` int(11) NOT NULL,
  `academic_session_id` int(11) DEFAULT NULL,
  `title` varchar(255) NOT NULL,
  `required_per_doctor` int(11) NOT NULL,
  `done` tinyint(1) NOT NULL DEFAULT 0,
  `required_count` int(11) NOT NULL DEFAULT 1,
  `notes` text DEFAULT NULL,
  `grade` decimal(5,2) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `task_assignments`
--

CREATE TABLE `task_assignments` (
  `id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `task_id` int(11) NOT NULL,
  `completed_count` int(11) DEFAULT 0,
  `academic_session_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `task_instances`
--

CREATE TABLE `task_instances` (
  `id` int(11) NOT NULL,
  `task_id` int(11) NOT NULL,
  `doctor_id` int(11) DEFAULT NULL,
  `status` enum('pending','assigned','completed') DEFAULT 'pending',
  `assigned_date` datetime DEFAULT NULL,
  `completion_date` datetime DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `grade` decimal(5,2) DEFAULT NULL,
  `assigned_by` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `task_progress`
--

CREATE TABLE `task_progress` (
  `id` int(11) NOT NULL,
  `task_id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `status` enum('pending','done') DEFAULT 'pending'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `tooth_conditions`
--

CREATE TABLE `tooth_conditions` (
  `id` int(11) NOT NULL,
  `dental_chart_id` int(11) NOT NULL,
  `tooth_number` varchar(10) NOT NULL,
  `tooth_position` enum('upper_right','upper_left','lower_right','lower_left') NOT NULL,
  `condition_type` enum('cavity','crack','discoloration','missing','healthy','decay','fracture','wear','other') NOT NULL,
  `severity` enum('mild','moderate','severe') DEFAULT 'moderate',
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `tooth_treatments`
--

CREATE TABLE `tooth_treatments` (
  `id` int(11) NOT NULL,
  `dental_chart_id` int(11) NOT NULL,
  `tooth_number` varchar(10) NOT NULL,
  `tooth_position` enum('upper_right','upper_left','lower_right','lower_left') NOT NULL,
  `treatment_type` enum('root_canal','restoration','extraction','filling','crown','bridge','implant','other') NOT NULL,
  `treatment_status` enum('planned','in_progress','completed','failed') DEFAULT 'planned',
  `treatment_notes` text DEFAULT NULL,
  `treatment_date` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `treatment_materials`
--

CREATE TABLE `treatment_materials` (
  `id` int(11) NOT NULL,
  `tooth_treatment_id` int(11) NOT NULL,
  `material_name` varchar(100) NOT NULL,
  `material_type` enum('filling','crown','bridge','implant','cement','other') NOT NULL,
  `quantity` decimal(10,2) DEFAULT 1.00,
  `unit` varchar(20) DEFAULT 'piece',
  `cost` decimal(10,2) DEFAULT 0.00,
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `treatment_plans`
--

CREATE TABLE `treatment_plans` (
  `id` int(11) NOT NULL,
  `chart_id` int(11) NOT NULL,
  `plan_date` date DEFAULT NULL,
  `plan_notes` text DEFAULT NULL,
  `mark` varchar(100) DEFAULT NULL,
  `doctor_name` varchar(255) DEFAULT NULL,
  `signature` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



-- --------------------------------------------------------

--
-- Table structure for table `tv_queue`
--

CREATE TABLE `tv_queue` (
  `id` int(11) NOT NULL,
  `patient_id` int(11) NOT NULL,
  `doctor_id` int(11) NOT NULL,
  `status` enum('waiting','called','finished') DEFAULT 'waiting'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `full_name` varchar(255) NOT NULL,
  `username` varchar(100) NOT NULL,
  `email` varchar(255) NOT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `password` varchar(255) NOT NULL,
  `role` enum('super_admin','admin','editor','doctor','accountant','senior','hr') NOT NULL DEFAULT 'editor',
  `status` enum('active','inactive') NOT NULL DEFAULT 'active',
  `notes` text DEFAULT NULL,
  `last_login` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT NULL ON UPDATE current_timestamp(),
  `profile_image` varchar(255) DEFAULT NULL,
  `last_activity` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



-- --------------------------------------------------------

--
-- Table structure for table `user_activity_log`
--

CREATE TABLE `user_activity_log` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `username` varchar(255) DEFAULT NULL,
  `user_role` varchar(50) DEFAULT NULL,
  `action` varchar(100) NOT NULL,
  `module` varchar(100) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `record_id` int(11) DEFAULT NULL,
  `data` text DEFAULT NULL,
  `details` text DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `request_method` varchar(10) DEFAULT NULL,
  `request_url` varchar(500) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `deleted_at` datetime DEFAULT NULL,
  `delete_after` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



-- --------------------------------------------------------

--
-- Table structure for table `user_allowed_departments`
--

CREATE TABLE `user_allowed_departments` (
  `user_id` int(11) NOT NULL,
  `department_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `user_allowed_education_types`
--

CREATE TABLE `user_allowed_education_types` (
  `user_id` int(11) NOT NULL,
  `education_type_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `user_allowed_stages`
--

CREATE TABLE `user_allowed_stages` (
  `user_id` int(11) NOT NULL,
  `stage_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



-- --------------------------------------------------------

--
-- Table structure for table `user_permissions`
--

CREATE TABLE `user_permissions` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `module` varchar(50) NOT NULL,
  `permission` varchar(50) NOT NULL,
  `granted` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



-- --------------------------------------------------------

--
-- Table structure for table `user_stage_department_permissions`
--

CREATE TABLE `user_stage_department_permissions` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `stage_id` int(11) NOT NULL,
  `department_id` int(11) NOT NULL,
  `can_view` tinyint(1) DEFAULT 0,
  `can_create` tinyint(1) DEFAULT 0,
  `can_edit` tinyint(1) DEFAULT 0,
  `can_delete` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;



--
-- Indexes for dumped tables
--

--
-- Indexes for table `academic_sessions`
--
ALTER TABLE `academic_sessions`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `appointments`
--
ALTER TABLE `appointments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `patient_id` (`patient_id`),
  ADD KEY `doctor_id` (`doctor_id`),
  ADD KEY `task_id` (`task_id`),
  ADD KEY `idx_pinned` (`pinned`);

--
-- Indexes for table `app_settings`
--
ALTER TABLE `app_settings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `setting_key` (`setting_key`);

--
-- Indexes for table `case_sheet_types`
--
ALTER TABLE `case_sheet_types`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `type_code` (`type_code`);

--
-- Indexes for table `clinics`
--
ALTER TABLE `clinics`
  ADD PRIMARY KEY (`id`),
  ADD KEY `phase_id` (`phase_id`);

--
-- Indexes for table `clinic_settings`
--
ALTER TABLE `clinic_settings`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `complete_denture_records`
--
ALTER TABLE `complete_denture_records`
  ADD PRIMARY KEY (`id`),
  ADD KEY `doctor_id` (`doctor_id`);

--
-- Indexes for table `dental_charts`
--
ALTER TABLE `dental_charts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `doctor_id` (`doctor_id`),
  ADD KEY `idx_patient_doctor` (`patient_id`,`doctor_id`),
  ADD KEY `idx_visit_date` (`visit_date`),
  ADD KEY `idx_task_instances` (`task_instances_id`);

--
-- Indexes for table `dental_follow_ups`
--
ALTER TABLE `dental_follow_ups`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_chart_followup` (`dental_chart_id`),
  ADD KEY `idx_followup_date` (`follow_up_date`),
  ADD KEY `idx_followup_status` (`status`);

--
-- Indexes for table `departments`
--
ALTER TABLE `departments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `stage_id` (`stage_id`),
  ADD KEY `education_type_id` (`education_type_id`);

--
-- Indexes for table `department_permissions`
--
ALTER TABLE `department_permissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_assignment_permission` (`role_assignment_id`,`permission_type`),
  ADD KEY `role_assignment_id` (`role_assignment_id`);

--
-- Indexes for table `department_role_activity_log`
--
ALTER TABLE `department_role_activity_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `role_assignment_id` (`role_assignment_id`),
  ADD KEY `performed_by` (`performed_by`),
  ADD KEY `created_at` (`created_at`);

--
-- Indexes for table `department_role_assignments`
--
ALTER TABLE `department_role_assignments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_user_dept_role` (`user_id`,`department_id`,`role_type`),
  ADD KEY `user_id` (`user_id`),
  ADD KEY `department_id` (`department_id`),
  ADD KEY `stage_id` (`stage_id`),
  ADD KEY `role_type` (`role_type`),
  ADD KEY `assigned_by` (`assigned_by`);

--
-- Indexes for table `doctors`
--
ALTER TABLE `doctors`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `username` (`username`),
  ADD KEY `education_type_id` (`education_type_id`),
  ADD KEY `stage_id` (`stage_id`);

--
-- Indexes for table `doctor_group_members`
--
ALTER TABLE `doctor_group_members`
  ADD PRIMARY KEY (`id`),
  ADD KEY `group_id` (`group_id`),
  ADD KEY `doctor_id` (`doctor_id`);

--
-- Indexes for table `doctor_tasks`
--
ALTER TABLE `doctor_tasks`
  ADD PRIMARY KEY (`id`),
  ADD KEY `doctor_id` (`doctor_id`),
  ADD KEY `task_id` (`task_id`);

--
-- Indexes for table `doctor_task_progress`
--
ALTER TABLE `doctor_task_progress`
  ADD KEY `doctor_id` (`doctor_id`),
  ADD KEY `task_id` (`task_id`),
  ADD KEY `status` (`status`);

--
-- Indexes for table `education_types`
--
ALTER TABLE `education_types`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `endodontics_images`
--
ALTER TABLE `endodontics_images`
  ADD PRIMARY KEY (`id`),
  ADD KEY `dental_chart_id` (`dental_chart_id`);

--
-- Indexes for table `groups`
--
ALTER TABLE `groups`
  ADD PRIMARY KEY (`id`),
  ADD KEY `stage_id` (`stage_id`);

--
-- Indexes for table `group_slots`
--
ALTER TABLE `group_slots`
  ADD PRIMARY KEY (`id`),
  ADD KEY `group_id` (`group_id`);

--
-- Indexes for table `mikrotik_settings`
--
ALTER TABLE `mikrotik_settings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `setting_key` (`setting_key`);

--
-- Indexes for table `oral_medicine_charts`
--
ALTER TABLE `oral_medicine_charts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_doctor` (`doctor_id`),
  ADD KEY `idx_task` (`task_instances_id`);

--
-- Indexes for table `orthodontics_records`
--
ALTER TABLE `orthodontics_records`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_doctor` (`doctor_id`),
  ADD KEY `idx_task` (`task_instances_id`);

--
-- Indexes for table `patients`
--
ALTER TABLE `patients`
  ADD PRIMARY KEY (`id`),
  ADD KEY `task_id` (`task_id`),
  ADD KEY `stage_id` (`stage_id`),
  ADD KEY `group_id` (`group_id`),
  ADD KEY `doctor_id` (`doctor_id`);

--
-- Indexes for table `patients_admin`
--
ALTER TABLE `patients_admin`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `patients_simple`
--
ALTER TABLE `patients_simple`
  ADD PRIMARY KEY (`id`),
  ADD KEY `phone` (`phone`),
  ADD KEY `created_at` (`created_at`);

--
-- Indexes for table `payments`
--
ALTER TABLE `payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `appointment_id` (`appointment_id`);

--
-- Indexes for table `periodontal_charts`
--
ALTER TABLE `periodontal_charts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `doctor_id` (`doctor_id`),
  ADD KEY `idx_patient_doctor` (`patient_id`,`doctor_id`),
  ADD KEY `idx_chart_date` (`chart_date`);

--
-- Indexes for table `permissions`
--
ALTER TABLE `permissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `role_id` (`role_id`,`page`);

--
-- Indexes for table `phases`
--
ALTER TABLE `phases`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `prevention_records`
--
ALTER TABLE `prevention_records`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_doctor` (`doctor_id`),
  ADD KEY `idx_task` (`task_instances_id`);

--
-- Indexes for table `prosthodontics_records`
--
ALTER TABLE `prosthodontics_records`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `register_days`
--
ALTER TABLE `register_days`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `register_day_service`
--
ALTER TABLE `register_day_service`
  ADD PRIMARY KEY (`day_id`,`service_name`);

--
-- Indexes for table `register_day_service_map`
--
ALTER TABLE `register_day_service_map`
  ADD PRIMARY KEY (`day_id`,`service_id`);

--
-- Indexes for table `register_services`
--
ALTER TABLE `register_services`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `roles`
--
ALTER TABLE `roles`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `role_permissions`
--
ALTER TABLE `role_permissions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `role_id` (`role_id`),
  ADD KEY `permission_id` (`permission_id`);

--
-- Indexes for table `role_stage_department_permissions`
--
ALTER TABLE `role_stage_department_permissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_role_stage_dept` (`role_id`,`stage_id`,`department_id`);

--
-- Indexes for table `stages`
--
ALTER TABLE `stages`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_stages_education_type` (`education_type_id`);

--
-- Indexes for table `surgeries`
--
ALTER TABLE `surgeries`
  ADD PRIMARY KEY (`id`),
  ADD KEY `patient_id` (`patient_id`),
  ADD KEY `doctor_id` (`doctor_id`),
  ADD KEY `surgery_date` (`surgery_date`),
  ADD KEY `status` (`status`);

--
-- Indexes for table `surgery_follow_ups`
--
ALTER TABLE `surgery_follow_ups`
  ADD PRIMARY KEY (`id`),
  ADD KEY `surgery_id` (`surgery_id`);

--
-- Indexes for table `surgery_images`
--
ALTER TABLE `surgery_images`
  ADD PRIMARY KEY (`id`),
  ADD KEY `surgery_id` (`surgery_id`);

--
-- Indexes for table `surgery_medications`
--
ALTER TABLE `surgery_medications`
  ADD PRIMARY KEY (`id`),
  ADD KEY `surgery_id` (`surgery_id`);

--
-- Indexes for table `tasks`
--
ALTER TABLE `tasks`
  ADD PRIMARY KEY (`id`),
  ADD KEY `department_id` (`department_id`),
  ADD KEY `fk_tasks_case_sheet_type` (`case_sheet_type_id`);

--
-- Indexes for table `task_assignments`
--
ALTER TABLE `task_assignments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `doctor_id` (`doctor_id`),
  ADD KEY `task_id` (`task_id`);

--
-- Indexes for table `task_instances`
--
ALTER TABLE `task_instances`
  ADD PRIMARY KEY (`id`),
  ADD KEY `assigned_by` (`assigned_by`),
  ADD KEY `idx_task_instances_task_id` (`task_id`),
  ADD KEY `idx_task_instances_doctor_id` (`doctor_id`),
  ADD KEY `idx_task_instances_status` (`status`);

--
-- Indexes for table `task_progress`
--
ALTER TABLE `task_progress`
  ADD PRIMARY KEY (`id`),
  ADD KEY `task_id` (`task_id`),
  ADD KEY `doctor_id` (`doctor_id`);

--
-- Indexes for table `tooth_conditions`
--
ALTER TABLE `tooth_conditions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_chart_tooth_condition` (`dental_chart_id`,`tooth_number`),
  ADD KEY `idx_condition_type` (`condition_type`);

--
-- Indexes for table `tooth_treatments`
--
ALTER TABLE `tooth_treatments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_chart_tooth` (`dental_chart_id`,`tooth_number`),
  ADD KEY `idx_treatment_type` (`treatment_type`),
  ADD KEY `idx_treatment_status` (`treatment_status`);

--
-- Indexes for table `treatment_materials`
--
ALTER TABLE `treatment_materials`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_treatment_material` (`tooth_treatment_id`),
  ADD KEY `idx_material_type` (`material_type`);

--
-- Indexes for table `treatment_plans`
--
ALTER TABLE `treatment_plans`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_chart_id` (`chart_id`),
  ADD KEY `idx_plan_date` (`plan_date`);

--
-- Indexes for table `tv_queue`
--
ALTER TABLE `tv_queue`
  ADD PRIMARY KEY (`id`),
  ADD KEY `patient_id` (`patient_id`),
  ADD KEY `doctor_id` (`doctor_id`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `username` (`username`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `user_activity_log`
--
ALTER TABLE `user_activity_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `user_id` (`user_id`),
  ADD KEY `action` (`action`),
  ADD KEY `created_at` (`created_at`);

--
-- Indexes for table `user_allowed_departments`
--
ALTER TABLE `user_allowed_departments`
  ADD PRIMARY KEY (`user_id`,`department_id`);

--
-- Indexes for table `user_allowed_education_types`
--
ALTER TABLE `user_allowed_education_types`
  ADD PRIMARY KEY (`user_id`,`education_type_id`);

--
-- Indexes for table `user_allowed_stages`
--
ALTER TABLE `user_allowed_stages`
  ADD PRIMARY KEY (`user_id`,`stage_id`);

--
-- Indexes for table `user_permissions`
--
ALTER TABLE `user_permissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `user_module_permission` (`user_id`,`module`,`permission`),
  ADD KEY `user_id` (`user_id`),
  ADD KEY `module` (`module`),
  ADD KEY `permission` (`permission`);

--
-- Indexes for table `user_stage_department_permissions`
--
ALTER TABLE `user_stage_department_permissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_user_stage_dept` (`user_id`,`stage_id`,`department_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `academic_sessions`
--
ALTER TABLE `academic_sessions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `appointments`
--
ALTER TABLE `appointments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=58;

--
-- AUTO_INCREMENT for table `app_settings`
--
ALTER TABLE `app_settings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `case_sheet_types`
--
ALTER TABLE `case_sheet_types`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT for table `clinics`
--
ALTER TABLE `clinics`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `complete_denture_records`
--
ALTER TABLE `complete_denture_records`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `dental_charts`
--
ALTER TABLE `dental_charts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=41;

--
-- AUTO_INCREMENT for table `dental_follow_ups`
--
ALTER TABLE `dental_follow_ups`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `departments`
--
ALTER TABLE `departments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;

--
-- AUTO_INCREMENT for table `department_permissions`
--
ALTER TABLE `department_permissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `department_role_activity_log`
--
ALTER TABLE `department_role_activity_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `department_role_assignments`
--
ALTER TABLE `department_role_assignments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `doctors`
--
ALTER TABLE `doctors`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=774;

--
-- AUTO_INCREMENT for table `doctor_group_members`
--
ALTER TABLE `doctor_group_members`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=277;

--
-- AUTO_INCREMENT for table `doctor_tasks`
--
ALTER TABLE `doctor_tasks`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `education_types`
--
ALTER TABLE `education_types`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT for table `endodontics_images`
--
ALTER TABLE `endodontics_images`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `groups`
--
ALTER TABLE `groups`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=36;

--
-- AUTO_INCREMENT for table `group_slots`
--
ALTER TABLE `group_slots`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=42;

--
-- AUTO_INCREMENT for table `mikrotik_settings`
--
ALTER TABLE `mikrotik_settings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=21;

--
-- AUTO_INCREMENT for table `oral_medicine_charts`
--
ALTER TABLE `oral_medicine_charts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `orthodontics_records`
--
ALTER TABLE `orthodontics_records`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `patients`
--
ALTER TABLE `patients`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=53;

--
-- AUTO_INCREMENT for table `patients_admin`
--
ALTER TABLE `patients_admin`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=52;

--
-- AUTO_INCREMENT for table `patients_simple`
--
ALTER TABLE `patients_simple`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=53;

--
-- AUTO_INCREMENT for table `payments`
--
ALTER TABLE `payments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `periodontal_charts`
--
ALTER TABLE `periodontal_charts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `permissions`
--
ALTER TABLE `permissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `phases`
--
ALTER TABLE `phases`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `prevention_records`
--
ALTER TABLE `prevention_records`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `prosthodontics_records`
--
ALTER TABLE `prosthodontics_records`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `register_days`
--
ALTER TABLE `register_days`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=165;

--
-- AUTO_INCREMENT for table `register_services`
--
ALTER TABLE `register_services`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=28;

--
-- AUTO_INCREMENT for table `roles`
--
ALTER TABLE `roles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `role_permissions`
--
ALTER TABLE `role_permissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT for table `role_stage_department_permissions`
--
ALTER TABLE `role_stage_department_permissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `stages`
--
ALTER TABLE `stages`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=21;

--
-- AUTO_INCREMENT for table `surgeries`
--
ALTER TABLE `surgeries`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=19;

--
-- AUTO_INCREMENT for table `surgery_follow_ups`
--
ALTER TABLE `surgery_follow_ups`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `surgery_images`
--
ALTER TABLE `surgery_images`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `surgery_medications`
--
ALTER TABLE `surgery_medications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=29;

--
-- AUTO_INCREMENT for table `tasks`
--
ALTER TABLE `tasks`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=38;

--
-- AUTO_INCREMENT for table `task_assignments`
--
ALTER TABLE `task_assignments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `task_instances`
--
ALTER TABLE `task_instances`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=116;

--
-- AUTO_INCREMENT for table `task_progress`
--
ALTER TABLE `task_progress`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `tooth_conditions`
--
ALTER TABLE `tooth_conditions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `tooth_treatments`
--
ALTER TABLE `tooth_treatments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=251;

--
-- AUTO_INCREMENT for table `treatment_materials`
--
ALTER TABLE `treatment_materials`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `treatment_plans`
--
ALTER TABLE `treatment_plans`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `tv_queue`
--
ALTER TABLE `tv_queue`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `user_activity_log`
--
ALTER TABLE `user_activity_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=392;

--
-- AUTO_INCREMENT for table `user_permissions`
--
ALTER TABLE `user_permissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=284;

--
-- AUTO_INCREMENT for table `user_stage_department_permissions`
--
ALTER TABLE `user_stage_department_permissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `appointments`
--
ALTER TABLE `appointments`
  ADD CONSTRAINT `appointments_ibfk_1` FOREIGN KEY (`patient_id`) REFERENCES `patients` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `appointments_ibfk_2` FOREIGN KEY (`doctor_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `appointments_ibfk_3` FOREIGN KEY (`task_id`) REFERENCES `tasks` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `clinics`
--
ALTER TABLE `clinics`
  ADD CONSTRAINT `clinics_ibfk_1` FOREIGN KEY (`phase_id`) REFERENCES `phases` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `complete_denture_records`
--
ALTER TABLE `complete_denture_records`
  ADD CONSTRAINT `complete_denture_records_ibfk_1` FOREIGN KEY (`doctor_id`) REFERENCES `doctors` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `dental_charts`
--
ALTER TABLE `dental_charts`
  ADD CONSTRAINT `dental_charts_ibfk_2` FOREIGN KEY (`doctor_id`) REFERENCES `doctors` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `dental_follow_ups`
--
ALTER TABLE `dental_follow_ups`
  ADD CONSTRAINT `dental_follow_ups_ibfk_1` FOREIGN KEY (`dental_chart_id`) REFERENCES `dental_charts` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `departments`
--
ALTER TABLE `departments`
  ADD CONSTRAINT `departments_ibfk_1` FOREIGN KEY (`stage_id`) REFERENCES `stages` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `departments_ibfk_2` FOREIGN KEY (`education_type_id`) REFERENCES `education_types` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `department_permissions`
--
ALTER TABLE `department_permissions`
  ADD CONSTRAINT `fk_dept_perm_assignment` FOREIGN KEY (`role_assignment_id`) REFERENCES `department_role_assignments` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `department_role_activity_log`
--
ALTER TABLE `department_role_activity_log`
  ADD CONSTRAINT `fk_dept_role_log_assignment` FOREIGN KEY (`role_assignment_id`) REFERENCES `department_role_assignments` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_dept_role_log_user` FOREIGN KEY (`performed_by`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `department_role_assignments`
--
ALTER TABLE `department_role_assignments`
  ADD CONSTRAINT `fk_dept_role_assigned_by` FOREIGN KEY (`assigned_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_dept_role_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_dept_role_stage` FOREIGN KEY (`stage_id`) REFERENCES `stages` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_dept_role_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `doctors`
--
ALTER TABLE `doctors`
  ADD CONSTRAINT `doctors_ibfk_1` FOREIGN KEY (`education_type_id`) REFERENCES `education_types` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `doctors_ibfk_2` FOREIGN KEY (`stage_id`) REFERENCES `stages` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `doctor_group_members`
--
ALTER TABLE `doctor_group_members`
  ADD CONSTRAINT `doctor_group_members_ibfk_1` FOREIGN KEY (`group_id`) REFERENCES `groups` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `doctor_group_members_ibfk_2` FOREIGN KEY (`doctor_id`) REFERENCES `doctors` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `endodontics_images`
--
ALTER TABLE `endodontics_images`
  ADD CONSTRAINT `endodontics_images_ibfk_1` FOREIGN KEY (`dental_chart_id`) REFERENCES `dental_charts` (`id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
