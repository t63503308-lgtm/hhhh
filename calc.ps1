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

# Deduplicate
$cleanList = @()
$seen = @{}
$dupCount = 0

foreach ($r in $rows) {
    $cols = $r.Split(',')
    $loanId = $cols[0].Trim()
    if ($seen.ContainsKey($loanId)) {
        $dupCount++
        continue
    }
    $seen[$loanId] = $true
    
    $obj = [PSCustomObject]@{
        LoanId = $loanId
        UserId = $cols[1].Trim()
        BookId = $cols[2].Trim()
        BookTitle = $cols[3].Trim()
        Category = $cols[4].Trim()
        BorrowDateStr = $cols[5].Trim()
        DueDateStr = $cols[6].Trim()
        ReturnDateStr = $cols[7].Trim()
        Status = $cols[8].Trim()
        
        BorrowDate = Parse-Date $cols[5].Trim()
        DueDate = Parse-Date $cols[6].Trim()
        ReturnDate = Parse-Date $cols[7].Trim()
        
        IsClean = $true
        Issue = ""
        EvalCategory = "" # OnTime, Late, OverdueUnreturned, NormalUnreturned, Unevaluable
        DurationDays = $null
        DelayDays = $null
        OverdueDays = $null
    }
    $cleanList += $obj
}

Write-Host "Total original rows: $($rows.Length)"
Write-Host "Duplicate removed: $dupCount"
Write-Host "Cleaned total unique rows: $($cleanList.Count)"

# Classify each record according to Section 5
foreach ($item in $cleanList) {
    # Check issues
    if ($item.LoanId -eq "L062") {
        $item.Issue = "รหัสหนังสือว่าง (เติม B003 ตามชื่อเรื่อง)"
        $item.BookId = "B003"
    }
    if ($item.LoanId -eq "L013") {
        $item.Issue = "หมวดหมู่มีเว้นวรรคส่วนเกิน (Trim แล้ว)"
    }
    if ($item.LoanId -eq "L029") {
        $item.Issue = "ลำดับเวลาขัดแย้ง: กำหนดคืน (10 พ.ย.) ก่อนวันยืม (12 พ.ย.)"
        $item.IsClean = $false
    }
    if ($item.LoanId -eq "L045") {
        $item.Issue = "ลำดับเวลาขัดแย้ง: วันคืนจริง (7 ก.ย.) ก่อนวันยืม (8 ก.ย.)"
        $item.IsClean = $false
    }
    if ($item.LoanId -eq "L080") {
        $item.Issue = "ข้อมูลขัดแย้ง: สถานะคือ 'คืนแล้ว' แต่วันที่คืนจริงเป็นค่าว่าง"
        $item.IsClean = $false
    }
    if ($item.LoanId -eq "L097") {
        $item.Issue = "ข้อมูลขัดแย้ง: สถานะคือ 'ยังไม่คืน' แต่วันที่คืนจริงมีระบุ (4 ต.ค.)"
        $item.IsClean = $false
    }
    if ($item.LoanId -eq "L114") {
        $item.Issue = "วันที่ไม่ถูกต้อง: วันยืม 2026-10-32 ไม่มีอยู่จริงในปฏิทิน"
        $item.IsClean = $false
    }

    # Evaluation
    # If not clean / unevaluable:
    if (-not $item.IsClean) {
        $item.EvalCategory = "ประเมินไม่ได้"
    } else {
        if ($item.Status -eq "คืนแล้ว") {
            if ($item.ReturnDate -ne $null -and $item.DueDate -ne $null -and $item.BorrowDate -ne $null) {
                $duration = ($item.ReturnDate - $item.BorrowDate).TotalDays
                $item.DurationDays = [int]$duration
                
                $delay = ($item.ReturnDate - $item.DueDate).TotalDays
                if ($delay -le 0) {
                    $item.EvalCategory = "คืนตรงเวลา"
                    $item.DelayDays = 0
                } else {
                    $item.EvalCategory = "คืนล่าช้า"
                    $item.DelayDays = [int]$delay
                }
            } else {
                $item.EvalCategory = "ประเมินไม่ได้"
            }
        } elseif ($item.Status -eq "ยังไม่คืน") {
            if ($item.DueDate -ne $null) {
                if ($refDate -gt $item.DueDate) {
                    $item.EvalCategory = "ยังไม่คืนเกินกำหนด"
                    $item.OverdueDays = [int](($refDate - $item.DueDate).TotalDays)
                } else {
                    $item.EvalCategory = "ยังไม่คืนไม่เกินกำหนด"
                    $item.OverdueDays = 0
                }
            } else {
                $item.EvalCategory = "ประเมินไม่ได้"
            }
        }
    }
}

# Stats
$groups = $cleanList | Group-Object EvalCategory
Write-Host "`n=== EVALUATION CATEGORIES ==="
$groups | Select-Object Name, Count | Format-Table -AutoSize

# Returned stats
$returnedClean = $cleanList | Where-Object { $_.EvalCategory -in @("คืนตรงเวลา", "คืนล่าช้า") }
$onTimeCount = ($returnedClean | Where-Object { $_.EvalCategory -eq "คืนตรงเวลา" }).Count
$lateCount = ($returnedClean | Where-Object { $_.EvalCategory -eq "คืนล่าช้า" }).Count
$totalEvalReturned = $returnedClean.Count

$onTimeRate = ($onTimeCount / $totalEvalReturned) * 100
Write-Host "`n=== RETURN STATS ==="
Write-Host "Returned Evaluable: $totalEvalReturned"
Write-Host "On-time: $onTimeCount ($($onTimeRate.ToString('F2'))%)"
Write-Host "Late: $lateCount"

# Unreturned stats
$unreturnedClean = $cleanList | Where-Object { $_.EvalCategory -in @("ยังไม่คืนเกินกำหนด", "ยังไม่คืนไม่เกินกำหนด") }
$overdueUnreturned = ($unreturnedClean | Where-Object { $_.EvalCategory -eq "ยังไม่คืนเกินกำหนด" }).Count
$normalUnreturned = ($unreturnedClean | Where-Object { $_.EvalCategory -eq "ยังไม่คืนไม่เกินกำหนด" }).Count
$totalEvalUnreturned = $unreturnedClean.Count
$overdueRate = ($overdueUnreturned / $totalEvalUnreturned) * 100

Write-Host "`n=== UNRETURNED STATS ==="
Write-Host "Unreturned Evaluable: $totalEvalUnreturned"
Write-Host "Overdue unreturned: $overdueUnreturned ($($overdueRate.ToString('F2'))%)"
Write-Host "Normal unreturned: $normalUnreturned"

# Overall KPIs
$uniqueUsers = ($cleanList | Select-Object -ExpandProperty UserId -Unique).Count
$totalUnreturnedAll = ($cleanList | Where-Object { $_.Status -eq "ยังไม่คืน" }).Count
Write-Host "`n=== KPIS ==="
Write-Host "1. Total Loans (Unique records): $($cleanList.Count)"
Write-Host "2. Unique Users: $uniqueUsers"
Write-Host "3. Total Unreturned: $totalUnreturnedAll (Clean evaluable unreturned: $totalEvalUnreturned)"
Write-Host "4. Overdue Unreturned: $overdueUnreturned"
Write-Host "5. On-Time Return Rate: $($onTimeRate.ToString('F2'))%"

# Duration stats for returnedClean
$durations = $returnedClean | Select-Object -ExpandProperty DurationDays | Sort-Object
$minDur = $durations[0]
$maxDur = $durations[-1]
$avgDur = ($durations | Measure-Object -Average).Average
$mid = [Math]::Floor($durations.Count / 2)
if ($durations.Count % 2 -eq 0) {
    $medDur = ($durations[$mid - 1] + $durations[$mid]) / 2.0
} else {
    $medDur = $durations[$mid]
}

# Standard deviation
$variance = ($durations | ForEach-Object { [Math]::Pow($_ - $avgDur, 2) } | Measure-Object -Sum).Sum / ($durations.Count - 1)
$stdDur = [Math]::Sqrt($variance)

Write-Host "`n=== DURATION STATS (Days) ==="
Write-Host "Min: $minDur, Max: $maxDur, Avg: $($avgDur.ToString('F2')), Median: $medDur, StdDev: $($stdDur.ToString('F2'))"

# Delay days stats for returnedClean
$delays = $returnedClean | Select-Object -ExpandProperty DelayDays | Sort-Object
$avgDelay = ($delays | Measure-Object -Average).Average
$maxDelay = $delays[-1]
Write-Host "`n=== DELAY STATS (Days for all returned) ==="
Write-Host "Avg Delay: $($avgDelay.ToString('F2')), Max Delay: $maxDelay"

$lateOnly = $returnedClean | Where-Object { $_.DelayDays -gt 0 } | Select-Object -ExpandProperty DelayDays
$avgLateOnly = ($lateOnly | Measure-Object -Average).Average
Write-Host "Avg Delay (late records only): $($avgLateOnly.ToString('F2')) days"

# Top 5 Popular Books
Write-Host "`n=== TOP 5 POPULAR BOOKS ==="
$cleanList | Group-Object BookTitle | Sort-Object Count -Descending | Select-Object -First 5 Name, Count | Format-Table -AutoSize

# Category distribution
Write-Host "`n=== CATEGORY DISTRIBUTION ==="
$cleanList | Group-Object Category | Sort-Object Count -Descending | Select-Object Name, Count | Format-Table -AutoSize

# Monthly trend
Write-Host "`n=== MONTHLY TREND ==="
$cleanList | Where-Object { $_.BorrowDate -ne $null } | Group-Object { $_.BorrowDate.ToString("yyyy-MM") } | Sort-Object Name | Select-Object Name, Count | Format-Table -AutoSize
