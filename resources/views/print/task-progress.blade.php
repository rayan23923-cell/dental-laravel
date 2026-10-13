@extends('print.layout')

{{-- Task progress report (2026-10-13, by request): the same table as the
     app's PDF (task_progress_pdf.dart) — one section per department, each
     doctor's task slots with status, grades and date. Printed from the
     browser, whose print dialog also saves it as PDF. --}}

@php
    $statusLabels = ['completed' => 'مكتملة', 'assigned' => 'قيد التنفيذ', 'pending' => 'معلّقة', 'unassigned' => 'لم تبدأ بعد'];
    $statusColors = ['completed' => '#16a34a', 'assigned' => '#2563eb', 'pending' => '#ea580c', 'unassigned' => '#9ca3af'];
    $subtitle = implode(' · ', array_filter([
        $group['id'] ? $group['name'] : null,
        $group['stage_name'] ?? null,
        $group['education_type_name'] ?? null,
        $scopeLine ?: null,
    ]));
    $date = fn ($v) => $v ? substr((string) $v, 0, 10) : '-';
@endphp

@section('title', 'تقرير تقدم المهام')

@section('back_url', url()->previous() ?: route('task-progress.index'))

@section('letterhead')
    <h2 style="margin-top:8px">تقرير تقدم المهام</h2>
    @if ($subtitle)
        <p>{{ $subtitle }}</p>
    @endif
@endsection

@section('content')
    <style>
        .status { display: inline-block; color: #fff; border-radius: 4px; padding: 1px 6px; font-size: 11px; }
        .progress td, .progress th { font-size: 12px; padding: 4px 6px; }
        @media print {
            @page { size: A4; margin: 10mm; }
            tr { break-inside: avoid; }
        }
    </style>

    @forelse ($departments as $department)
        <h3 class="section">{{ $department['name'] }}</h3>
        <table class="progress">
            <thead>
                <tr><th>#</th><th>اسم الطبيب</th><th>المهمة</th><th>الحالة</th><th>درجة المهمة</th><th>الدرجة المحققة</th><th>التاريخ</th></tr>
            </thead>
            <tbody>
                @foreach ($department['doctors'] as $doctor)
                    @foreach ($doctor['tasks'] as $i => $card)
                        <tr>
                            <td>{{ $i + 1 }}</td>
                            @if ($i === 0)
                                <td rowspan="{{ count($doctor['tasks']) }}">{{ $doctor['name'] }}</td>
                            @endif
                            <td>{{ $card['task_title'] }} ({{ $card['slot'] }})</td>
                            <td><span class="status" style="background: {{ $statusColors[$card['status']] ?? '#9ca3af' }}">{{ $statusLabels[$card['status']] ?? $card['status'] }}</span></td>
                            <td>{{ $card['task_grade'] ?? '-' }}</td>
                            <td>{{ $card['grade'] ?? '-' }}</td>
                            <td>{{ $date($card['completion_date'] ?? $card['assigned_date']) }}</td>
                        </tr>
                    @endforeach
                @endforeach
            </tbody>
        </table>
    @empty
        <p class="muted" style="text-align:center">لا توجد مهام للطباعة.</p>
    @endforelse

    @if ($autoprint)
        <script>window.addEventListener('load', () => setTimeout(() => window.print(), 300));</script>
    @endif
@endsection
