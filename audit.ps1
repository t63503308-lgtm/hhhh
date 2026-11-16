$lines = Get-Content -Encoding UTF8 "library_book_loans_dirty_150.csv"
$rows = $lines[1..($lines.Length - 1)]

function Parse-Date($s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    try {
        return [DateTime]::ParseExact($s.Trim(), "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return "INVALID"
    }
}

$refDate = [DateTime]::ParseExact("2026-11-15", "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)

$seenIds = @{}
$issues = @()

$lineIdx = 1
foreach ($r in $rows) {
    $lineIdx++
    $cols = $r.Split(',')
    $loanId = $cols[0].Trim()
    $userId = $cols[1].Trim()
    $bookId = $cols[2].Trim()
    $bookName = $cols[3].Trim()
    $catRaw = $cols[4]
    $cat = $catRaw.Trim()
    $bDateRaw = $cols[5].Trim()
    $dueDateRaw = $cols[6].Trim()
    $retDateRaw = $cols[7].Trim()
    $status = $cols[8].Trim()

    # Check 1: Duplicate Loan ID
    if ($seenIds.ContainsKey($loanId)) {
        $issues += [PSCustomObject]@{ Line=$lineIdx; LoanId=$loanId; IssueType="DUPLICATE_ID"; Detail="Loan ID $loanId duplicates row $($seenIds[$loanId])" }
    } else {
        $seenIds[$loanId] = $lineIdx
    }

    # Check 2: Missing Book ID
    if ([string]::IsNullOrEmpty($bookId)) {
        $issues += [PSCustomObject]@{ Line=$lineIdx; LoanId=$loanId; IssueType="MISSING_BOOK_ID"; Detail="Book ID is missing for '$bookName'" }
    }

    # Check 3: Whitespace in Category
    if ($catRaw -ne $cat) {
        $issues += [PSCustomObject]@{ Line=$lineIdx; LoanId=$loanId; IssueType="WHITESPACE_CATEGORY"; Detail="Category '$catRaw' has leading/trailing whitespace" }
    }

    # Check 4: Date parsing
    $dBorrow = Parse-Date $bDateRaw
    $dDue = Parse-Date $dueDateRaw
    $dRet = Parse-Date $retDateRaw

    if ($dBorrow -eq "INVALID") {
        $issues += [PSCustomObject]@{ Line=$lineIdx; LoanId=$loanId; IssueType="INVALID_BORROW_DATE"; Detail="Borrow date '$bDateRaw' is not a valid date" }
    }
    if ($dDue -eq "INVALID") {
        $issues += [PSCustomObject]@{ Line=$lineIdx; LoanId=$loanId; IssueType="INVALID_DUE_DATE"; Detail="Due date '$dueDateRaw' is not a valid date" }
    }
    if ($dRet -eq "INVALID") {
        $issues += [PSCustomObject]@{ Line=$lineIdx; LoanId=$loanId; IssueType="INVALID_RETURN_DATE"; Detail="Return date '$retDateRaw' is not a valid date" }
    }

    # Check 5: Chronology (Due < Borrow)
    if ($dBorrow -is [DateTime] -and $dDue -is [DateTime]) {
        if ($dDue -lt $dBorrow) {
            $issues += [PSCustomObject]@{ Line=$lineIdx; LoanId=$loanId; IssueType="CHRONO_DUE_BEFORE_BORROW"; Detail="Due date ($dueDateRaw) is earlier than borrow date ($bDateRaw)" }
        }
    }

    # Check 6: Chronology (Return < Borrow)
    if ($dBorrow -is [DateTime] -and $dRet -is [DateTime]) {
        if ($dRet -lt $dBorrow) {
            $issues += [PSCustomObject]@{ Line=$lineIdx; LoanId=$loanId; IssueType="CHRONO_RETURN_BEFORE_BORROW"; Detail="Return date ($retDateRaw) is earlier than borrow date ($bDateRaw)" }
        }
    }

    # Check 7: Status conflict: Returned but no return date
    if ($status -eq "คืนแล้ว" -and [string]::IsNullOrEmpty($retDateRaw)) {
        $issues += [PSCustomObject]@{ Line=$lineIdx; LoanId=$loanId; IssueType="CONFLICT_STATUS_NO_RETDATE"; Detail="Status is 'คืนแล้ว' but return date is empty" }
    }

    # Check 8: Status conflict: Not returned but has return date
    if ($status -eq "ยังไม่คืน" -and -not [string]::IsNullOrEmpty($retDateRaw)) {
        $issues += [PSCustomObject]@{ Line=$lineIdx; LoanId=$loanId; IssueType="CONFLICT_STATUS_HAS_RETDATE"; Detail="Status is 'ยังไม่คืน' but return date is '$retDateRaw'" }
    }
}

Write-Host "Total Issues Found: $($issues.Count)"
$issues | Format-Table -AutoSize
