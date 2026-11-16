$lines = Get-Content -Encoding UTF8 "library_book_loans_clean_149.csv"
$header = $lines[0].Split(',')
$rows = $lines[1..($lines.Length - 1)]

$data = @()
foreach ($r in $rows) {
    $cols = $r.Split(',')
    $item = [PSCustomObject]@{
        loan_id = $cols[0]
        user_id = $cols[1]
        book_id = $cols[2]
        book_title = $cols[3]
        category = $cols[4]
        borrow_date = $cols[5]
        due_date = $cols[6]
        return_date = $cols[7]
        return_status = $cols[8]
        eval_status = $cols[9]
        borrow_duration = if ($cols[10] -ne "") { [int]$cols[10] } else { $null }
        delay_days = if ($cols[11] -ne "") { [int]$cols[11] } else { $null }
        clean_note = $cols[12]
    }
    $data += $item
}

$json = $data | ConvertTo-Json -Depth 5 -Compress
$jsContent = "// Cleaned Library Loans Dataset (149 unique records)`nwindow.LIBRARY_CLEAN_DATA = $json;`n"

# Also raw audit log
$auditLog = @(
    @{
        id = "ERR-001"
        loan_id = "L130"
        field = "รหัสการยืม (loan_id) และข้อมูลทั้งแถว"
        error_type = "ข้อมูลซ้ำ (Duplicate Record)"
        severity = "สูง (High)"
        original_value = "ปรากฏ 2 แถวข้อมูลเหมือนกันทุกฟิลด์ (แถวที่ 131 และ 132)"
        cleaned_value = "นับเพียง 1 รายการ (ตัดแถวซ้ำออก 1 รายการ)"
        rule_ref = "ข้อกำหนด 4.1 และ 4.3: ข้อมูลซ้ำให้นับครั้งเดียว"
        reason = "เกิดจากการบันทึกซ้ำซ้อนในระบบฐานข้อมูลเดิม การตัดแถวซ้ำออกทำให้ไม่นับจำนวนการยืมเกินจริง"
        status = "แก้ไขแล้ว (Cleaned)"
        eval_impact = "จำนวนเรคคอร์ดจาก 150 เหลือ 149 รายการ"
    },
    @{
        id = "ERR-002"
        loan_id = "L013"
        field = "หมวดหมู่ (category)"
        error_type = "ช่องว่างส่วนเกิน (Whitespace)"
        severity = "ต่ำ (Low)"
        original_value = "' เทคโนโลยี '"
        cleaned_value = "'เทคโนโลยี'"
        rule_ref = "ข้อกำหนด 4.1: ตรวจความสอดคล้องของข้อความ"
        reason = "มีช่องว่าง (whitespace) นำหน้าและต่อท้ายคำว่าเทคโนโลยี ตัดแต่งด้วย .trim() เพื่อให้การจัดกลุ่มหมวดหมู่ถูกต้อง"
        status = "แก้ไขแล้ว (Cleaned)"
        eval_impact = "สามารถประเมินผลได้ตามปกติ รวมอยู่ในหมวดเทคโนโลยี"
    },
    @{
        id = "ERR-003"
        loan_id = "L062"
        field = "รหัสหนังสือ (book_id)"
        error_type = "ค่าว่างสูญหาย (Missing Value)"
        severity = "ปานกลาง (Medium)"
        original_value = "ค่าว่าง (Empty String)"
        cleaned_value = "'B003'"
        rule_ref = "ข้อกำหนด 4.1 และ 4.4: ตรวจค่าว่างและความสอดคล้อง"
        reason = "ชื่อเรื่องคือ 'สร้างเว็บไซต์เบื้องต้น' ซึ่งในระบบมีรหัสหนังสือ B003 เพียงรหัสเดียวในทุกเรคคอร์ด จึงเติม B003 พร้อมบันทึกหลักฐาน"
        status = "แก้ไขแล้วพร้อมบันทึก (Imputed & Documented)"
        eval_impact = "สามารถประเมินผลได้ตามปกติ จัดเป็นคืนตรงเวลา (ยืม 2 วัน)"
    },
    @{
        id = "ERR-004"
        loan_id = "L029"
        field = "กำหนดคืน (due_date) vs วันที่ยืม (borrow_date)"
        error_type = "ลำดับเวลาขัดแย้ง (Chronological Inversion)"
        severity = "สูง (High)"
        original_value = "วันที่ยืม 2026-11-12 แต่กำหนดคืน 2026-11-10"
        cleaned_value = "คงค่าเดิมไว้ และระบุสถานะ 'ประเมินไม่ได้ / รอตรวจสอบ'"
        rule_ref = "ข้อกำหนด 4.2 และ 4.3: หากข้อมูลขัดแย้งให้แสดงว่ารอตรวจสอบ ห้ามเดาความจริง"
        reason = "กำหนดคืนมาก่อนวันยืม ซึ่งขัดกับหลักตรรกะและลำดับเหตุการณ์จริง ห้ามเดาวันที่เอง จึงแยกออกจากการคำนวณวันล่าช้า"
        status = "รอตรวจสอบ (Pending Audit)"
        eval_impact = "แยกออกจากการประเมินความล่าช้า จัดอยู่ในกลุ่มประเมินไม่ได้"
    },
    @{
        id = "ERR-005"
        loan_id = "L045"
        field = "วันที่คืนจริง (return_date) vs วันที่ยืม (borrow_date)"
        error_type = "ลำดับเวลาขัดแย้ง (Chronological Inversion)"
        severity = "สูง (High)"
        original_value = "วันที่ยืม 2026-09-08 แต่วันที่คืนจริง 2026-09-07"
        cleaned_value = "คงค่าเดิมไว้ และระบุสถานะ 'ประเมินไม่ได้ / รอตรวจสอบ'"
        rule_ref = "ข้อกำหนด 4.2: ตรวจความถูกต้องของวันที่และลำดับเหตุการณ์"
        reason = "วันคืนจริงมาก่อนวันยืม ส่งผลให้ระยะเวลายืมติดลบ (-1 วัน) ซึ่งเป็นไปไม่ได้ในความเป็นจริง ห้ามเดาวันที่เอง"
        status = "รอตรวจสอบ (Pending Audit)"
        eval_impact = "แยกออกจากการคำนวณสถิติระยะเวลายืม จัดอยู่ในกลุ่มประเมินไม่ได้"
    },
    @{
        id = "ERR-006"
        loan_id = "L080"
        field = "วันที่คืนจริง (return_date) vs สถานะการคืน (return_status)"
        error_type = "ข้อมูลขัดแย้งกับสถานะ (Status-Date Conflict)"
        severity = "สูง (High)"
        original_value = "สถานะ = 'คืนแล้ว' แต่วันที่คืนจริงเป็นค่าว่าง"
        cleaned_value = "คงค่าเดิมไว้ และระบุสถานะ 'ประเมินไม่ได้ / รอตรวจสอบ'"
        rule_ref = "ข้อกำหนด 4.2 และ 4.3: รายการที่ยังไม่คืนอาจไม่มีวันที่คืนจริงได้ตามปกติ ห้ามเติมวันที่คืนขึ้นเอง"
        reason = "สถานะระบุว่าคืนแล้ว แต่ไม่มีวันที่คืนจริง ทำให้ไม่สามารถทราบได้ว่าคืนตรงเวลาหรือล่าช้ากี่วัน ห้ามเติมวันที่คืนเอง"
        status = "รอตรวจสอบ (Pending Audit)"
        eval_impact = "แยกออกจากการคำนวณอัตราคืนตรงเวลาและสถิติวันยืมถึงคืน"
    },
    @{
        id = "ERR-007"
        loan_id = "L097"
        field = "วันที่คืนจริง (return_date) vs สถานะการคืน (return_status)"
        error_type = "ข้อมูลขัดแย้งกับสถานะ (Status-Date Conflict)"
        severity = "สูง (High)"
        original_value = "สถานะ = 'ยังไม่คืน' แต่วันที่คืนจริงระบุ '2026-10-04'"
        cleaned_value = "คงค่าเดิมไว้ และระบุสถานะ 'ประเมินไม่ได้ / รอตรวจสอบ'"
        rule_ref = "ข้อกำหนด 4.2: หากข้อมูลขัดแย้งหรือขาดหลักฐาน ให้แสดงว่ารอตรวจสอบ ห้ามเดาความจริง"
        reason = "สถานะระบุยังไม่คืน แต่วันที่คืนจริงมีระบุวันที่ไว้ ขัดแย้งกันโดยตรง อาจเกิดจากการลงวันที่คืนแต่ลืมเปลี่ยนสถานะ หรือใส่ผิดเรคคอร์ด"
        status = "รอตรวจสอบ (Pending Audit)"
        eval_impact = "แยกออกจากการคำนวณอัตราค้างส่งเกินกำหนด จนกว่าจะยืนยันตัวเล่มจริง"
    },
    @{
        id = "ERR-008"
        loan_id = "L114"
        field = "วันที่ยืม (borrow_date)"
        error_type = "รูปแบบวันที่ผิดปฏิทิน (Invalid Calendar Date)"
        severity = "สูง (High)"
        original_value = "'2026-10-32'"
        cleaned_value = "คงค่าเดิมไว้ และระบุสถานะ 'ประเมินไม่ได้ / รอตรวจสอบ'"
        rule_ref = "ข้อกำหนด 4.2: ตรวจความถูกต้องของวันที่ ห้ามเดาความจริง"
        reason = "เดือนตุลาคมมีเพียง 31 วัน วันที่ 2026-10-32 จึงไม่มีอยู่จริงในปฏิทิน แม้คาดว่าอาจเป็น 31 ต.ค. หรือ 1 พ.ย. แต่ตามกติกาห้ามเดาความจริง"
        status = "รอตรวจสอบ (Pending Audit)"
        eval_impact = "แยกออกจากการคำนวณระยะเวลายืม จัดอยู่ในกลุ่มประเมินไม่ได้"
    }
)

$auditJson = $auditLog | ConvertTo-Json -Depth 5 -Compress
$jsContent += "`nwindow.LIBRARY_AUDIT_LOG = $auditJson;`n"

# Also raw 150 records for comparison
$rawLines = Get-Content -Encoding UTF8 "library_book_loans_dirty_150.csv"
$rawRows = $rawLines[1..($rawLines.Length - 1)]
$rawData = @()
$rIdx = 0
foreach ($r in $rawRows) {
    $rIdx++
    $cols = $r.Split(',')
    $rawData += [PSCustomObject]@{
        row_num = $rIdx
        loan_id = $cols[0].Trim()
        user_id = $cols[1].Trim()
        book_id = $cols[2].Trim()
        book_title = $cols[3].Trim()
        category = $cols[4]
        borrow_date = $cols[5].Trim()
        due_date = $cols[6].Trim()
        return_date = $cols[7].Trim()
        return_status = $cols[8].Trim()
    }
}
$rawJson = $rawData | ConvertTo-Json -Depth 5 -Compress
$jsContent += "`nwindow.LIBRARY_RAW_DATA = $rawJson;`n"

$jsContent | Out-File -Encoding utf8 "js\library_data.js"
Write-Host "Created js\library_data.js successfully."
