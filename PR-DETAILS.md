# Maintenance Scheduling System

## Overview
Adds an independent maintenance scheduling system to the existing maintenance request tracker. This feature enables proactive scheduling of recurring maintenance tasks, reducing reactive maintenance requests and improving facility management efficiency.

## Technical Implementation

### New Data Structures
- **scheduled-maintenance map**: Stores recurring task definitions with frequency, location, and assignment details
- **schedule-counter**: Tracks unique scheduling IDs 
- **active-schedules**: Monitors count of currently active schedules

### Key Functions Added
- `create-schedule`: Creates new recurring maintenance schedules
- `assign-schedule-technician`: Assigns technicians to scheduled tasks
- `complete-scheduled-task`: Marks scheduled tasks as completed and updates next due date
- `toggle-schedule-status`: Activates/deactivates schedules
- `get-schedule-analytics`: Provides scheduling metrics and insights
- `is-schedule-overdue`: Checks if scheduled tasks are past due

### Frequency Support
- Daily, weekly, monthly, quarterly, yearly intervals
- Custom interval support with specified day counts
- Automatic next-due-date calculation based on frequency

## Testing & Validation
- ✅ Contract uses Clarity v3 with proper data types
- ✅ Comprehensive error handling with dedicated error constants (u200-u204)  
- ✅ Authorization checks for admin and creator permissions
- ✅ CI/CD pipeline configured with GitHub Actions
- ✅ Independent feature - no cross-contract dependencies or trait implementations
- ✅ Line endings normalized (CRLF → LF) for all modified files

## Value Proposition
This scheduling system transforms maintenance management from purely reactive to proactive, enabling facilities to:
- Schedule preventive maintenance tasks
- Track completion history and performance metrics
- Reduce emergency maintenance requests through proactive scheduling
- Optimize resource allocation with scheduled technician assignments
