$lines = Get-Content -Encoding UTF8 "library_book_loans_dirty_150.csv"
$rows = $lines[1..($lines.Length - 1)]

function Parse-Date($s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    try {
        return [DateTime]::ParseExact($s.Trim(), "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $null
    }
}

$refDate = [DateTime]::ParseExact("2026-11-15", "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)

$cleanRows = @()
$seen = @{}
$header = "รหัสการยืม,รหัสผู้ยืม,รหัสหนังสือ,ชื่อหนังสือ,หมวดหมู่,วันที่ยืม,กำหนดคืน,วันที่คืนจริง,สถานะการคืน,กลุ่มสถานะประเมิน,วันยืมถึงคืน,วันล่าช้า_เกินกำหนด,หมายเหตุการคลีน"
$cleanRows += $header

foreach ($r in $rows) {
    $cols = $r.Split(',')
    $loanId = $cols[0].Trim()
    
    # Check duplicate
    if ($seen.ContainsKey($loanId)) {
        continue # Remove duplicate L130
    }
    $seen[$loanId] = $true

    $userId = $cols[1].Trim()
    $bookId = $cols[2].Trim()
    $bookTitle = $cols[3].Trim()
    $cat = $cols[4].Trim()
    $bDateStr = $cols[5].Trim()
    $dueDateStr = $cols[6].Trim()
    $retDateStr = $cols[7].Trim()
    $status = $cols[8].Trim()
    
    $note = "ปกติ"
    $evalCat = "รอประเมิน"
    $durationStr = ""
    $delayStr = ""

    # Address anomalies
    if ($loanId -eq "L013") {
        $note = "แก้ไข: ตัดช่องว่างหมวดหมู่"
    }
    if ($loanId -eq "L062") {
        $bookId = "B003"
        $note = "แก้ไข: เติมรหัสหนังสือ B003 ตามชื่อเรื่อง"
    }
    if ($loanId -eq "L029") {
        $note = "ผิดปกติ: กำหนดคืนก่อนวันยืม (รอตรวจสอบ)"
        $evalCat = "ประเมินไม่ได้"
    }
    if ($loanId -eq "L045") {
        $note = "ผิดปกติ: วันคืนจริงก่อนวันยืม (รอตรวจสอบ)"
        $evalCat = "ประเมินไม่ได้"
    }
    if ($loanId -eq "L080") {
        $note = "ผิดปกติ: คืนแล้วแต่วันที่คืนจริงว่าง (รอตรวจสอบ)"
        $evalCat = "ประเมินไม่ได้"
    }
    if ($loanId -eq "L097") {
        $note = "ผิดปกติ: ยังไม่คืนแต่วันที่คืนจริงมีค่า (รอตรวจสอบ)"
        $evalCat = "ประเมินไม่ได้"
    }
    if ($loanId -eq "L114") {
        $note = "ผิดปกติ: วันยืม 2026-10-32 ผิดปฏิทิน (รอตรวจสอบ)"
        $evalCat = "ประเมินไม่ได้"
    }

    $dBorrow = Parse-Date $bDateStr
    $dDue = Parse-Date $dueDateStr
    $dRet = Parse-Date $retDateStr

    if ($evalCat -ne "ประเมินไม่ได้") {
        if ($status -eq "คืนแล้ว") {
            if ($dRet -ne $null -and $dDue -ne $null -and $dBorrow -ne $null) {
                $dur = [int](($dRet - $dBorrow).TotalDays)
                $durationStr = $dur.ToString()
                $delay = [int](($dRet - $dDue).TotalDays)
                if ($delay -le 0) {
                    $evalCat = "คืนตรงเวลา"
                    $delayStr = "0"
                } else {
                    $evalCat = "คืนล่าช้า"
                    $delayStr = $delay.ToString()
                }
            } else {
                $evalCat = "ประเมินไม่ได้"
            }
        } elseif ($status -eq "ยังไม่คืน") {
            if ($dDue -ne $null) {
                if ($refDate -gt $dDue) {
                    $evalCat = "ยังไม่คืนเกินกำหนด"
                    $overdue = [int](($refDate - $dDue).TotalDays)
                    $delayStr = $overdue.ToString()
                } else {
                    $evalCat = "ยังไม่คืนไม่เกินกำหนด"
                    $delayStr = "0"
                }
            } else {
                $evalCat = "ประเมินไม่ได้"
            }
        }
    }

    $cleanRows += "$loanId,$userId,$bookId,$bookTitle,$cat,$bDateStr,$dueDateStr,$retDateStr,$status,$evalCat,$durationStr,$delayStr,$note"
}

$cleanRows | Out-File -Encoding utf8 "library_book_loans_clean_149.csv"
Write-Host "Created library_book_loans_clean_149.csv with $($cleanRows.Count - 1) data rows."
