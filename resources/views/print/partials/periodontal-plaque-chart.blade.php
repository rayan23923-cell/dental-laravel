{{--
    Periodontal's "Plaque Index" per-visit dental chart — ported from
    dental_clinics2/doctor/periodontal_chart_print_html.php's own
    `createToothSVG()`/`renderDentalChartJS()` (client-side JS there;
    server-rendered here, same "print must not depend on a script having
    run before Ctrl+P" rule as every other chart in this app — see
    CaseSheetPrintRenderer::charts()'s own doc comment). A completely
    separate feature from the BOP/PPD/CAL measurement grids above, despite
    sharing the same `chart_data` column — see App\Support\PlaqueChart's
    own doc comment.

    $visits is a ready list of ['label' => ..., 'data' => PlaqueChart::visitData(...)]
    — already filtered to visits that actually have data — built by the
    includer (CaseSheetPrintController::show()).
--}}
@php
    $toothShapes = \App\Support\PlaqueChart::TOOTH_SHAPES;
    $upperTeeth = \App\Support\PlaqueChart::UPPER_TEETH;
    $lowerTeeth = \App\Support\PlaqueChart::LOWER_TEETH;

    // Same 4-triangle sector split as the original's own `quadrants` array
    // (width=height=40, cx=cy=20) — buccal/distal/lingual/mesial fanning
    // out from the tooth's centre to each edge midpoint... actually to
    // each corner pair, matching the original exactly.
    $sectorPoints = [
        'buccal' => '0,0 40,0 20,20',
        'distal' => '40,0 40,40 20,20',
        'lingual' => '40,40 0,40 20,20',
        'mesial' => '0,40 0,0 20,20',
    ];

    $toothCounter = 0;
    $renderPlaqueTooth = function ($toothId, $type, $toothData) use ($toothShapes, $sectorPoints, &$toothCounter) {
        $toothCounter++;
        $clipId = 'plaque-clip-'.$toothId.'-'.$toothCounter;
        $pathData = $toothShapes[$type] ?? $toothShapes['molar'];
        $extracted = $toothData['extracted'] ?? false;
        $surfaces = $toothData['surfaces'] ?? [];

        $svg = '<svg width="28" height="28" viewBox="0 0 40 40" style="display:inline-block;margin:1px;">';
        $svg .= '<defs><clipPath id="'.$clipId.'"><path d="'.$pathData.'"/></clipPath></defs>';
        $svg .= '<g clip-path="url(#'.$clipId.')">';
        foreach ($sectorPoints as $name => $points) {
            $marked = ! $extracted && ($surfaces[$name] ?? false);
            $fill = $marked ? '#4caf50' : 'white';
            $opacity = $marked ? '0.7' : '0';
            $svg .= '<polygon points="'.$points.'" fill="'.$fill.'" fill-opacity="'.$opacity.'" stroke="none"/>';
        }
        $svg .= '</g>';
        $svg .= '<path d="'.$pathData.'" fill="none" stroke="#333" stroke-width="1"/>';
        $svg .= '<text x="20" y="24" text-anchor="middle" font-size="10" font-weight="bold" fill="#333">'.$toothId.'</text>';
        if ($extracted) {
            $svg .= '<path d="M 0,0 L 40,40 M 40,0 L 0,40" stroke="red" stroke-width="2" fill="none"/>';
        }
        $svg .= '</svg>';

        return $svg;
    };
@endphp

@foreach ($visits as $visit)
    <div class="section-title" style="display:flex;justify-content:space-between;">
        <span>{{ $visit['label'] }}</span>
        <span>Plaque Index: {{ $visit['data']['plaque_index'] }}% (Marked Surfaces: {{ $visit['data']['marked_surfaces'] }} / Total: {{ $visit['data']['total_surfaces'] }})</span>
    </div>
    <div style="border:1px solid #000;padding:4px;margin-bottom:6px;">
        <div style="text-align:center;font-weight:bold;font-size:8pt;">Upper Arch</div>
        <div style="text-align:center;line-height:0;">
            @foreach ($upperTeeth as $toothId => $type)
                {!! $renderPlaqueTooth($toothId, $type, $visit['data']['teeth'][$toothId] ?? []) !!}
            @endforeach
        </div>
        <div style="text-align:center;font-weight:bold;font-size:8pt;margin-top:4px;">Lower Arch</div>
        <div style="text-align:center;line-height:0;">
            @foreach ($lowerTeeth as $toothId => $type)
                {!! $renderPlaqueTooth($toothId, $type, $visit['data']['teeth'][$toothId] ?? []) !!}
            @endforeach
        </div>
        <div style="margin-top:6px;font-size:7pt;text-align:center;">
            <span style="display:inline-block;width:10px;height:10px;background:#4caf50;opacity:0.7;border:1px solid #ccc;vertical-align:middle;"></span>
            Plaque Present
            &nbsp;&nbsp;
            <span style="color:red;">✕</span> Extracted/Missing
        </div>
    </div>
@endforeach
