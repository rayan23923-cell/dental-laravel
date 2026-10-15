{{-- Single-series bar chart as inline SVG for the printed payments report
     (2026-10-12). Same drawing as resources/js/Components/BarChart.vue:
     one hue, rounded bar tops on a zero baseline, three labelled ticks.
     Expects $data = [['key' =>, 'label' =>, 'total' =>], ...]. --}}
@php
    $W = 700; $H = 200;
    $pl = 44; $pr = 8; $pt = 12; $pb = 24;
    $plotW = $W - $pl - $pr; $plotH = $H - $pt - $pb;
    $raw = max(0, ...array_map(fn ($d) => $d['total'], $data));
    if ($raw <= 0) { $max = 1; } else {
        $mag = 10 ** floor(log10($raw)); $n = $raw / $mag;
        $max = ($n <= 1 ? 1 : ($n <= 2 ? 2 : ($n <= 5 ? 5 : 10))) * $mag;
    }
    $count = max(1, count($data));
    $step = $plotW / $count;
    $barW = max(2, min(28, $step * 0.6));
    $every = (int) ceil($count / 12);
    $y = fn ($v) => $pt + $plotH - ($v / $max) * $plotH;
    // Compact tick labels (250K, 2M) so they fit the gutter.
    $compact = fn ($v) => $v >= 1e6 ? rtrim(rtrim(number_format($v / 1e6, 1), '0'), '.') . 'M'
        : ($v >= 1e3 ? rtrim(rtrim(number_format($v / 1e3, 1), '0'), '.') . 'K' : (string) $v);
@endphp
<svg viewBox="0 0 {{ $W }} {{ $H }}" style="width:100%; height:auto; display:block" role="img" aria-label="{{ $title ?? '' }}">
    @foreach ([0, $max / 2, $max] as $tk)
        <line x1="{{ $pl }}" x2="{{ $W - $pr }}" y1="{{ $y($tk) }}" y2="{{ $y($tk) }}" stroke="#d1d5db" stroke-width="1" />
        <text x="{{ $pl - 6 }}" y="{{ $y($tk) + 4 }}" text-anchor="end" font-size="11" fill="#4b5563" direction="ltr">{{ $compact($tk) }}</text>
    @endforeach
    @foreach ($data as $i => $d)
        @php
            $x = $pl + $i * $step + ($step - $barW) / 2;
            $top = $y($d['total']); $h = $pt + $plotH - $top; $base = $top + $h;
            $r = min(4, $barW / 2, $h);
        @endphp
        @if ($h > 0)
            <path d="M{{ $x }},{{ $base }} V{{ $top + $r }} Q{{ $x }},{{ $top }} {{ $x + $r }},{{ $top }} H{{ $x + $barW - $r }} Q{{ $x + $barW }},{{ $top }} {{ $x + $barW }},{{ $top + $r }} V{{ $base }} Z" fill="#4f46e5" />
        @endif
        @if ($i % $every === 0)
            <text x="{{ $x + $barW / 2 }}" y="{{ $H - 6 }}" text-anchor="middle" font-size="11" fill="#4b5563" direction="ltr">{{ $d['label'] }}</text>
        @endif
    @endforeach
</svg>
