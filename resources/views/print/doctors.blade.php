@extends('print.layout')

@section('title', 'قائمة الأطباء')

@section('letterhead')
    <p><strong>المرحلة:</strong> {{ $stageLabel }}</p>
@endsection

@section('content')
    @forelse ($byStage as $stage => $doctors)
        <h3 class="section">المرحلة: {{ $stage }} ({{ $doctors->count() }} طبيب/ة)</h3>
        <table>
            <thead>
                <tr>
                    <th style="width:5%">#</th>
                    <th style="width:25%">الاسم</th>
                    <th style="width:30%">البريد الإلكتروني</th>
                    <th style="width:20%">نوع الدراسة</th>
                    <th style="width:20%">المجموعة</th>
                </tr>
            </thead>
            <tbody>
                @foreach ($doctors as $i => $doctor)
                    <tr>
                        <td>{{ $i + 1 }}</td>
                        <td>{{ $doctor->name }}</td>
                        <td>{{ $doctor->email }}</td>
                        <td>{{ $doctor->educationType?->name ?? '-' }}</td>
                        <td>{{ $doctor->groups->pluck('name')->implode('، ') ?: '-' }}</td>
                    </tr>
                @endforeach
            </tbody>
        </table>
    @empty
        <p class="muted" style="text-align:center">لا يوجد أطباء مطابقون للفلتر المحدد.</p>
    @endforelse

    @if ($total > 0)
        <div class="summary">
            <h3>ملخص القائمة</h3>
            @foreach ($byStage as $stage => $doctors)
                <div class="summary-row">
                    <span>{{ $stage }}</span>
                    <strong>{{ $doctors->count() }}</strong>
                </div>
            @endforeach
            <div class="summary-row" style="border-top:1px solid #d1d5db; margin-top:6px; padding-top:6px">
                <span><strong>الإجمالي</strong></span>
                <strong>{{ $total }}</strong>
            </div>
        </div>

        <div class="signatures">
            <div class="signature">توقيع المشرف</div>
            <div class="signature">توقيع رئيس القسم</div>
        </div>
    @endif
@endsection
