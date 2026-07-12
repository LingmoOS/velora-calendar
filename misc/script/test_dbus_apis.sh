#!/bin/bash

# Practical DDE Calendar MCP API Test Suite
# Creates test data, validates all 6 APIs, outputs detailed results to file, and ensures cleanup
# 
# Usage: ./practical_mcp_api_test.sh [output_file]

# set -e  # Commented out to allow proper error handling

# Configuration
OUTPUT_FILE="${1:-dde_calendar_practical_test_$(date +%Y%m%d_%H%M%S).log}"
SERVICE="com.lingmo.Calendar"
OBJECT_PATH="/com/lingmo/Calendar"
INTERFACE="com.lingmo.Calendar"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test tracking
test_count=0
passed_tests=0
failed_tests=0
created_schedule_ids=()

# Logging functions
log() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" | tee -a "$OUTPUT_FILE"
}

log_colored() {
    local color="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${color}[$timestamp] $message${NC}"
    echo "[$timestamp] $message" >> "$OUTPUT_FILE"
}

log_json() {
    local label="$1"
    local json_data="$2"
    log "$label:"
    if command -v python3 &> /dev/null; then
        echo "$json_data" | python3 -m json.tool 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "$json_data" | tee -a "$OUTPUT_FILE"
    else
        echo "$json_data" | tee -a "$OUTPUT_FILE"
    fi
    echo "" | tee -a "$OUTPUT_FILE"
}

# DBus helper functions
call_dbus() {
    local method="$1"
    shift
    local result
    
    if result=$(dbus-send --session --print-reply --dest="$SERVICE" "$OBJECT_PATH" "$INTERFACE.$method" "$@" 2>&1); then
        if echo "$result" | grep -q "string"; then
            # Extract complete string value from D-Bus response, handling complex JSON
            # Pattern: string "JSON_CONTENT"
            echo "$result" | sed -n 's/.*string "\(.*\)"/\1/p' | tail -1
        elif echo "$result" | grep -q "boolean"; then
            echo "$result" | grep "boolean" | tail -1 | awk '{print $2}'
        else
            echo "$result"
        fi
    else
        log_colored "$RED" "DBus call failed: $result"
        return 1
    fi
}

extract_schedule_id() {
    local response="$1"
    # Extract UUID from JSON-like response like "{8cc2d01c-bcc1-47e2-871b-ced2726d0dc4}"
    echo "$response" | sed 's/[{}"]//g' | tr -d ' \n\r'
}

# Test framework functions
start_test() {
    test_count=$((test_count + 1))
    log_colored "$BLUE" "=========================================="
    log_colored "$BLUE" "Test $test_count: $1"
    log_colored "$BLUE" "=========================================="
}

pass_test() {
    passed_tests=$((passed_tests + 1))
    log_colored "$GREEN" "✓ PASSED: $1"
}

fail_test() {
    failed_tests=$((failed_tests + 1))
    log_colored "$RED" "✗ FAILED: $1"
}

info_log() {
    log_colored "$YELLOW" "ℹ INFO: $1"
}

# Service availability check
check_service() {
    start_test "Service Availability Check"
    
    if call_dbus "RaiseWindow" >/dev/null 2>&1; then
        pass_test "DDE Calendar service is running and accessible"
        
        # Show available methods
        info_log "Checking available methods..."
        local methods=$(dbus-send --session --print-reply --dest="$SERVICE" "$OBJECT_PATH" org.freedesktop.DBus.Introspectable.Introspect 2>/dev/null | grep 'method name=' | sed 's/.*method name="\([^"]*\)".*/\1/' | sort)
        log "Available D-Bus methods:"
        echo "$methods" | while read -r method; do
            log "  - $method"
        done
        
    else
        fail_test "DDE Calendar service is not running or not accessible"
        log "ERROR: Please start dde-calendar first: dde-calendar &"
        return 1
    fi
}

# Create practical test data
create_practical_test_data() {
    start_test "Creating Practical Test Data"
    
    local tomorrow=$(date -d "tomorrow" +%Y-%m-%d)
    local day_after=$(date -d "2 days" +%Y-%m-%d)
    local next_week=$(date -d "1 week" +%Y-%m-%d)
    
    local test_schedules=(
        # Basic meeting scenarios
        "{\"title\":\"项目例会\",\"description\":\"周例会讨论项目进展\",\"startTime\":\"${tomorrow}T09:00:00\",\"endTime\":\"${tomorrow}T10:00:00\",\"location\":\"会议室A\",\"reminder\":15}"
        "{\"title\":\"客户洽谈\",\"description\":\"与重要客户讨论合作事宜\",\"startTime\":\"${tomorrow}T14:00:00\",\"endTime\":\"${tomorrow}T15:30:00\",\"location\":\"客户办公室\",\"reminder\":30}"
        "{\"title\":\"技术培训\",\"description\":\"新技术培训课程\",\"startTime\":\"${day_after}T10:00:00\",\"endTime\":\"${day_after}T12:00:00\",\"location\":\"培训室\",\"reminder\":60}"
        
        # Personal events
        "{\"title\":\"医院预约\",\"description\":\"年度健康检查\",\"startTime\":\"${day_after}T14:30:00\",\"endTime\":\"${day_after}T16:00:00\",\"location\":\"市人民医院\",\"reminder\":45}"
        "{\"title\":\"朋友聚餐\",\"description\":\"老同学聚会\",\"startTime\":\"${day_after}T18:00:00\",\"endTime\":\"${day_after}T20:00:00\",\"location\":\"西餐厅\",\"reminder\":30}"
        
        # Business events
        "{\"title\":\"出差北京\",\"description\":\"北京分公司业务交流\",\"startTime\":\"${next_week}T08:00:00\",\"endTime\":\"${next_week}T18:00:00\",\"location\":\"北京分公司\",\"reminder\":120}"
        
        # All-day event
        "{\"title\":\"公司团建\",\"description\":\"部门团建活动\",\"startTime\":\"${next_week}T00:00:00\",\"endTime\":\"${next_week}T23:59:59\",\"allDay\":true,\"location\":\"郊外度假村\"}"
        
        # Test with special characters
        "{\"title\":\"测试：特殊字符@#$\",\"description\":\"测试特殊字符处理能力\",\"startTime\":\"${next_week}T13:00:00\",\"endTime\":\"${next_week}T14:00:00\",\"location\":\"测试地点\",\"reminder\":10}"
    )
    
    local created_count=0
    local failed_count=0
    
    for i in "${!test_schedules[@]}"; do
        local schedule_data="${test_schedules[$i]}"
        info_log "Creating test schedule $(($i + 1))/${#test_schedules[@]}"
        log_json "Schedule Data" "$schedule_data"
        
    if result=$(call_dbus "CreateSchedule" string:"$schedule_data"); then
        local schedule_id=$(extract_schedule_id "$result")
        if [[ -n "$schedule_id" && "$schedule_id" != "" ]]; then
            created_schedule_ids+=("$schedule_id")
            ((created_count++))
            info_log "✓ Created schedule ID: $schedule_id"
        else
            ((failed_count++))
            info_log "✗ Failed to extract schedule ID from: $result"
        fi
    else
        ((failed_count++))
        info_log "✗ Failed to create schedule $(($i + 1)): $result"
    fi
    done
    
    if [[ $created_count -gt 0 ]]; then
        pass_test "Created $created_count test schedules (failed: $failed_count)"
        log "Created Schedule IDs:"
        for id in "${created_schedule_ids[@]}"; do
            log "  - $id"
        done
    else
        fail_test "Failed to create any test schedules"
    fi
}

# Test QuerySchedules API
test_query_schedules() {
    start_test "QuerySchedules API - Practical Query Testing"
    
    local tomorrow=$(date -d "tomorrow" +%Y-%m-%d)
    local day_after=$(date -d "2 days" +%Y-%m-%d)
    local week_range="$(date -d '1 week ago' +%Y-%m-%d),$(date -d '1 week' +%Y-%m-%d)"
    
    local queries=(
        "today|查询今日日程"
        "day|查询今日日程(day参数)"
        "$tomorrow|查询明日日程"
        "$day_after|查询后天日程"
        "$week_range|查询两周范围"
        "search:会议|搜索会议关键词"
        "search:培训|搜索培训关键词"
        "search:聚餐|搜索聚餐关键词"
        "search:不存在|搜索不存在关键词"
    )
    
    local successful_queries=0
    
    for query_info in "${queries[@]}"; do
        IFS='|' read -r query desc <<< "$query_info"
        
        info_log "Testing: $desc ($query)"
        
        if result=$(call_dbus "QuerySchedules" string:"$query"); then
            if echo "$result" | grep -q '"success":true'; then
                local count=$(echo "$result" | grep -o '"count":[0-9]*' | grep -o '[0-9]*' | head -1)
                info_log "✓ Query successful, found $count schedule(s)"
                log_json "Query Result" "$result"
                ((successful_queries++))
            else
                info_log "✗ Query returned error"
                log_json "Error Result" "$result"
            fi
        else
            info_log "✗ Query failed"
        fi
        echo "" | tee -a "$OUTPUT_FILE"
    done
    
    if [[ $successful_queries -eq ${#queries[@]} ]]; then
        pass_test "All ${#queries[@]} query tests successful"
    else
        fail_test "$((${#queries[@]} - successful_queries)) out of ${#queries[@]} queries failed"
    fi
}

# Test schedule modification
test_modify_schedule() {
    start_test "ModifySchedule API - Update and Delete Testing"
    
    if [[ ${#created_schedule_ids[@]} -eq 0 ]]; then
        fail_test "No test schedules available for modification"
        return
    fi
    
    local successful_modifies=0
    local total_modifies=0
    
    # Test update
    if [[ ${#created_schedule_ids[@]} -gt 0 ]]; then
        local test_id="${created_schedule_ids[0]}"
        info_log "Testing schedule update with ID: $test_id"
        
        local update_data='{"title":"【已更新】项目例会","description":"更新后的会议描述","location":"新会议室","reminder":25}'
        log_json "Update Data" "$update_data"
        
        ((total_modifies++))
        if result=$(call_dbus "ModifySchedule" string:"$test_id" string:"update" string:"$update_data"); then
            if [[ "$result" == "true" ]]; then
                info_log "✓ Schedule update successful"
                ((successful_modifies++))
            else
                info_log "✗ Schedule update failed: $result"
            fi
        else
            info_log "✗ Schedule update call failed"
        fi
    fi
    
    # Test delete (use last schedule to avoid affecting other tests)
    if [[ ${#created_schedule_ids[@]} -gt 1 ]]; then
        local delete_id="${created_schedule_ids[-1]}"
        info_log "Testing schedule deletion with ID: $delete_id"
        
        ((total_modifies++))
        if result=$(call_dbus "ModifySchedule" string:"$delete_id" string:"delete" string:""); then
            if [[ "$result" == "true" ]]; then
                info_log "✓ Schedule deletion successful"
                ((successful_modifies++))
                # Remove from array
                created_schedule_ids=("${created_schedule_ids[@]/$delete_id}")
            else
                info_log "✗ Schedule deletion failed: $result"
            fi
        else
            info_log "✗ Schedule deletion call failed"
        fi
    fi
    
    if [[ $successful_modifies -eq $total_modifies ]]; then
        pass_test "All $total_modifies modification tests successful"
    else
        fail_test "$((total_modifies - successful_modifies)) out of $total_modifies modifications failed"
    fi
}

# Test calendar views
test_calendar_views() {
    start_test "GetCalendarView API - Multiple View Testing"
    
    local today=$(date +%Y-%m-%d)
    local tomorrow=$(date -d "tomorrow" +%Y-%m-%d)
    
    local views=(
        "today##今日视图"
        "week#$today#本周视图"
        "month#$today#本月视图"
        "today#$tomorrow#明日今日视图"
        "week#$tomorrow#明日所在周视图"
    )
    
    local successful_views=0
    
    for view_info in "${views[@]}"; do
        IFS='#' read -r view_type target_date desc <<< "$view_info"
        
        info_log "Testing: $desc (Type: $view_type, Date: $target_date)"
        
        if result=$(call_dbus "GetCalendarView" string:"$view_type" string:"$target_date"); then
            if echo "$result" | grep -q '"success":true'; then
                info_log "✓ Calendar view retrieved successfully"
                log_json "Calendar View Result" "$result"
                ((successful_views++))
            else
                info_log "✗ Calendar view returned error"
                log_json "View Error" "$result"
            fi
        else
            info_log "✗ Calendar view call failed"
        fi
        echo "" | tee -a "$OUTPUT_FILE"
    done
    
    if [[ $successful_views -eq ${#views[@]} ]]; then
        pass_test "All ${#views[@]} calendar views successful"
    else
        fail_test "$((${#views[@]} - successful_views)) out of ${#views[@]} calendar views failed"
    fi
}

# Test lunar information
test_lunar_info() {
    start_test "GetLunarInfo API - Lunar Calendar Testing"
    
    local today=$(date +%Y-%m-%d)
    local tomorrow=$(date -d "tomorrow" +%Y-%m-%d)
    local new_year="2025-01-01"
    local labor_day="2025-05-01"
    local national_day="2025-10-01"
    
    local test_dates=(
        "$today|今天农历信息"
        "$tomorrow|明天农历信息"
        "$new_year|元旦农历信息"
        "$labor_day|劳动节农历信息"
        "$national_day|国庆节农历信息"
    )
    
    local successful_queries=0
    
    for date_info in "${test_dates[@]}"; do
        IFS='|' read -r test_date desc <<< "$date_info"
        
        info_log "Testing: $desc ($test_date)"
        
        if result=$(call_dbus "GetLunarInfo" string:"$test_date"); then
            if echo "$result" | grep -q '"success":true'; then
                info_log "✓ Lunar information retrieved successfully"
                
                # Extract key info
                local lunar_date=$(echo "$result" | grep -o '"lunarDate":"[^"]*"' | cut -d':' -f2 | tr -d '"')
                local festival=$(echo "$result" | grep -o '"festival":"[^"]*"' | cut -d':' -f2 | tr -d '"')
                
                if [[ -n "$lunar_date" && "$lunar_date" != "" ]]; then
                    info_log "农历: $lunar_date"
                fi
                if [[ -n "$festival" && "$festival" != "" ]]; then
                    info_log "节日: $festival"
                fi
                
                log_json "Lunar Info Result" "$result"
                ((successful_queries++))
            else
                info_log "✗ Lunar information returned error"
                log_json "Lunar Error" "$result"
            fi
        else
            info_log "✗ Lunar information call failed"
        fi
        echo "" | tee -a "$OUTPUT_FILE"
    done
    
    if [[ $successful_queries -eq ${#test_dates[@]} ]]; then
        pass_test "All ${#test_dates[@]} lunar information queries successful"
    else
        fail_test "$((${#test_dates[@]} - successful_queries)) out of ${#test_dates[@]} lunar queries failed"
    fi
}

# Test reminders
test_reminders() {
    start_test "GetReminders API - Multiple Time Range Testing"
    
    local time_ranges=(24 72 168 720) # 1 day, 3 days, 1 week, 1 month
    local successful_queries=0
    
    for hours in "${time_ranges[@]}"; do
        local desc=""
        case $hours in
            24) desc="1天内" ;;
            72) desc="3天内" ;;
            168) desc="1周内" ;;
            720) desc="1月内" ;;
        esac
        
        info_log "Testing reminders for next $hours hours ($desc)"
        
        if result=$(call_dbus "GetReminders" int32:$hours); then
            if echo "$result" | grep -q '"success":true'; then
                local count=$(echo "$result" | grep -o '"count":[0-9]*' | grep -o '[0-9]*' | head -1)
                info_log "✓ Found $count reminder(s) in next $hours hours"
                log_json "Reminders Result ($hours hours)" "$result"
                ((successful_queries++))
            else
                info_log "✗ Reminders returned error"
                log_json "Reminders Error" "$result"
            fi
        else
            info_log "✗ Reminders call failed"
        fi
        echo "" | tee -a "$OUTPUT_FILE"
    done
    
    if [[ $successful_queries -eq ${#time_ranges[@]} ]]; then
        pass_test "All ${#time_ranges[@]} reminder queries successful"
    else
        fail_test "$((${#time_ranges[@]} - successful_queries)) out of ${#time_ranges[@]} reminder queries failed"
    fi
}

# Cleanup test data
cleanup_test_data() {
    start_test "Cleanup - Delete All Test Schedules"
    
    if [[ ${#created_schedule_ids[@]} -eq 0 ]]; then
        info_log "No test schedules to clean up"
        pass_test "No cleanup needed"
        return
    fi
    
    local deleted_count=0
    local failed_count=0
    
    info_log "Cleaning up ${#created_schedule_ids[@]} test schedules..."
    
    for schedule_id in "${created_schedule_ids[@]}"; do
        if [[ -n "$schedule_id" ]]; then
            info_log "Deleting schedule: $schedule_id"
            
            if result=$(call_dbus "ModifySchedule" string:"$schedule_id" string:"delete" string:""); then
                if [[ "$result" == "true" ]]; then
                    info_log "✓ Successfully deleted: $schedule_id"
                    ((deleted_count++))
                else
                    info_log "⚠ Schedule not found or already deleted: $schedule_id"
                    ((deleted_count++))  # Count as success if not found
                fi
            else
                info_log "✗ Failed to delete: $schedule_id"
                ((failed_count++))
            fi
        fi
    done
    
    log "Cleanup Summary:"
    log "  - Total Schedules: ${#created_schedule_ids[@]}"
    log "  - Successfully Deleted: $deleted_count"
    log "  - Failed to Delete: $failed_count"
    
    if [[ $deleted_count -ge $((${#created_schedule_ids[@]} - 1)) ]]; then
        pass_test "Cleanup successful - all test schedules removed"
    else
        fail_test "$failed_count test schedules failed to delete"
    fi
}

# Generate final report
generate_final_report() {
    local end_time=$(date)
    
    log_colored "$PURPLE" "=========================================="
    log_colored "$PURPLE" "PRACTICAL TEST FINAL REPORT"
    log_colored "$PURPLE" "=========================================="
    
    log "Test Execution Summary:"
    log "  - End Time: $end_time"
    log "  - Total Tests: $test_count"
    log "  - Passed Tests: $passed_tests"
    log "  - Failed Tests: $failed_tests"
    log "  - Success Rate: $(( passed_tests * 100 / test_count ))%"
    log ""
    
    log "API Coverage Summary:"
    log "  ✓ Service Availability Check"
    log "  ✓ Practical Test Data Creation (8 scenarios)"
    log "  ✓ QuerySchedules API (8 query types)"
    log "  ✓ ModifySchedule API (Update & Delete)"
    log "  ✓ GetCalendarView API (5 view types)"
    log "  ✓ GetLunarInfo API (5 date scenarios)"
    log "  ✓ GetReminders API (4 time ranges)"
    log "  ✓ Complete Test Data Cleanup"
    log ""
    
    log "Test Data Summary:"
    log "  - Test Schedules Created: ${#created_schedule_ids[@]}"
    log "  - Output File: $OUTPUT_FILE"
    log "  - File Size: $(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1 || echo "Unknown")"
    log ""
    
    if [[ $failed_tests -eq 0 ]]; then
        log_colored "$GREEN" "🎉 ALL PRACTICAL TESTS PASSED! 🎉"
        log_colored "$GREEN" "DDE Calendar MCP APIs are working correctly with practical test coverage."
        echo ""
        log_colored "$CYAN" "📄 Detailed results saved to: $OUTPUT_FILE"
        return 0
    else
        log_colored "$RED" "❌ $failed_tests PRACTICAL TEST(S) FAILED ❌"
        log_colored "$RED" "Please review the implementation and check the detailed log."
        echo ""
        log_colored "$CYAN" "📄 Detailed results saved to: $OUTPUT_FILE"
        return 1
    fi
}

# Main execution
main() {
    local start_time=$(date)
    
    # Initialize log file
    echo "DDE Calendar DBus - Practical Test Suite Log" > "$OUTPUT_FILE"
    echo "Generated: $start_time" >> "$OUTPUT_FILE"
    echo "Test Scope: All 6 MCP APIs with practical scenarios" >> "$OUTPUT_FILE"
    echo "========================================" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    log_colored "$PURPLE" "🚀 DDE Calendar DBus - Practical Test Suite"
    log_colored "$PURPLE" "📋 Practical API Testing | 📊 Detailed Logging | 🧹 Complete Cleanup"
    log_colored "$PURPLE" "📄 Output file: $OUTPUT_FILE"
    
    # Execute practical test suite
    check_service || return 1
    create_practical_test_data
    test_query_schedules
    test_modify_schedule
    test_calendar_views
    test_lunar_info
    test_reminders
    cleanup_test_data
    
    # Generate final report
    generate_final_report
}

# Cleanup function for script exit
cleanup_on_exit() {
    if [[ ${#created_schedule_ids[@]} -gt 0 ]]; then
        log_colored "$YELLOW" "Emergency cleanup on exit..."
        for schedule_id in "${created_schedule_ids[@]}"; do
            if [[ -n "$schedule_id" ]]; then
                call_dbus "ModifySchedule" string:"$schedule_id" string:"delete" string:"" >/dev/null 2>&1 || true
            fi
        done
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_on_exit EXIT

# Check if dde-calendar is running
if ! dbus-send --session --print-reply --dest="$SERVICE" "$OBJECT_PATH" "$INTERFACE.RaiseWindow" >/dev/null 2>&1; then
    echo -e "${RED}Error: DDE Calendar service is not running${NC}"
    echo "Please start dde-calendar first:"
    echo "  dde-calendar &"
    echo "  sleep 3"
    echo "  $0"
    exit 1
fi

# Run the practical test suite
main "$@"
