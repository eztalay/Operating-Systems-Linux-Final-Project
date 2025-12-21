# Operating-Systems-Linux-Final-Project

This project is a Linux Operating Systems assignment that simulates how companies manage employee accounts in a Linux environment. The purpose of the project is to demonstrate how employee onboarding and offboarding processes can be automated using shell scripting while ensuring proper logging, reporting, and system consistency.

The script reads employee information from a CSV file and synchronizes the Linux system state with this data. By doing so, it mimics real-world IT administration practices where user lifecycle management is automated to reduce manual workload and prevent configuration errors.

---

## Data Source and Lifecycle Logic

The main data source of the project is the `employees.csv` file. Each record in this file contains the following fields:

- employee_id  
- username  
- name_surname  
- department  
- status  

The `status` field determines the lifecycle action for each employee:

- **active** employees must exist on the system and belong to their corresponding department group  
- **terminated** employees must be offboarded, meaning their home directories are archived and their accounts are locked  

To detect changes between executions, the script compares the current `employees.csv` file with a previously saved snapshot file named `last_employees.csv`. This comparison allows the system to automatically identify newly added users, removed users, and terminated users and handle them accordingly.



## Execution Requirements

Before running the script, it must be made executable:

```bash
chmod +x employee_lifecycle_sync.sh 
```

Since the script performs system-level operations such as creating users, creating groups, and modifying accounts, it must be executed with superuser privileges:

```bash
sudo ./employee_lifecycle_sync.sh
```

## Script Operations 

During execution, the script performs the following operations:

-Creates department groups if they do not already exist

-Creates Linux user accounts for employees marked as active

-Assigns users to their corresponding department groups

-Detects employees marked as terminated

-Archives the home directories of terminated users into compressed .tar.gz files

-Locks terminated user accounts to prevent further access

-Generates detailed logs and summary reports for traceability

The script is designed to handle both first-time execution and subsequent runs by using the snapshot comparison mechanism.


## Output Structure

All generated files and artifacts are stored under the output/ directory with the following structure:

output/
├── logs/
│   └── run_<timestamp>.log
├── reports/
│   └── manager_report_<timestamp>.txt
├── archives/
│   └── <username>_<timestamp>.tar.gz
└── last_employees.csv

logs/ contains detailed execution logs for each script run

reports/ contains summary manager reports showing onboarding and offboarding statistics

archives/ stores compressed backups of terminated users’ home directories

last_employees.csv stores the snapshot used for change detection in future executions


## Email Notification

The script includes an optional email notification feature that attempts to send the generated manager report using the mail command.
If the mail utility is not available or email services are not configured, the script safely skips this step and records the situation in the log file without interrupting execution.

This behavior allows the script to run correctly in test environments such as WSL without requiring email configuration.


## Summary

This project provides an automated employee lifecycle management system on Linux. By integrating CSV-based data processing, snapshot comparison, user and group management, logging, reporting, and optional email notifications, the project demonstrates core concepts of Linux system administration, shell scripting, and automation in a realistic and structured manner.

