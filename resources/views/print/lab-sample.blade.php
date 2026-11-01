@extends('print.layout')

@section('title', 'عينات المريض — ' . $registration->name)

@section('back_url', route('lab.index'))

@section('no_letterhead', '1')

@section('content')
    {{-- "بدء الفحص" (2026-11-01, by request): the samples are placed on the
         circle, under the patient's name, so they are never mixed up. --}}
    <style>
        .sample-sheet { max-width: 420px; margin: 24px auto; text-align: center; color: #000; }
        .sample-sheet .title { font-size: 22px; font-weight: 600; margin: 0 0 10px; }
        .sample-sheet .name { font-size: 34px; font-weight: 800; border: 3px solid #000; padding: 10px 8px; line-height: 1.3; }
        .sample-sheet .sub { font-size: 17px; margin-top: 6px; }
        .sample-sheet .circle { width: 340px; height: 340px; margin: 18px auto 12px; border: 5px solid #000; border-radius: 50%;
            display: flex; align-items: center; justify-content: center; padding: 40px; box-sizing: border-box;
            font-size: 30px; font-weight: 700; line-height: 1.4; }
        .sample-sheet .foot { font-size: 19px; font-weight: 600; }
        .sample-sheet .date { font-size: 15px; }
        @media print {
            @page { size: 80mm auto; margin: 2mm; }
            .watermark { display: none !important; }
            .sample-sheet { max-width: none; margin: 0; }
            .sample-sheet .name { font-size: 26px; }
            .sample-sheet .circle { width: 64mm; height: 64mm; font-size: 24px; padding: 8mm; }
        }
    </style>
    <div class="sample-sheet">
        <p class="title">عينات المريض</p>
        <div class="name">{{ $registration->name }}</div>
        @if ($registration->service)
            <div class="sub">{{ $registration->service->name }}</div>
        @endif
        <div class="circle">هنا توضع العينات</div>
        <div class="foot">{{ $registration->name }}</div>
        <div class="date" dir="ltr">{{ now()->format('Y-m-d H:i') }}</div>
    </div>

    @if ($autoprint)
        <script>window.addEventListener('load', () => setTimeout(() => window.print(), 300));</script>
    @endif
@endsection
