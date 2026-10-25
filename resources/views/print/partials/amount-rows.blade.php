{{-- The amount rows of a paid slip. A discounted patient gets the amount,
     the discount and the amount after it on separate rows (2026-10-25, by
     request: "1000, خصم 50%, 500"); everyone else one `$label` row.
     Expects $registration, $paid, $full, $label and $currency (optional
     $paidText: how the plain row writes the amount; $fullLabel: the first
     row's name when discounted). --}}
@php($discount = \App\Support\StudentDiscount::breakdown($registration, (float) $paid, $full))
@if ($discount && $discount['percent'] !== null)
    <tr><th>{{ $fullLabel ?? 'المبلغ' }}</th><td>{{ number_format($discount['full']) }} {{ $currency }}</td></tr>
    <tr><th>التخفيض</th><td>{{ $discount['percent'] }}% — {{ $discount['who'] }}</td></tr>
    <tr><th>المبلغ بعد التخفيض</th><td><strong>{{ number_format($discount['paid']) }} {{ $currency }}</strong></td></tr>
@else
    <tr><th>{{ $label }}</th><td>{{ $paidText ?? number_format((float) $paid) }} {{ $currency }}</td></tr>
    @if ($discount)
        <tr><th>التخفيض</th><td>{{ $discount['who'] }}</td></tr>
    @endif
@endif
