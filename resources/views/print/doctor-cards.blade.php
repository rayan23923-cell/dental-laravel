@extends('print.layout')

@section('title', 'بطاقات الأطباء')
{{-- Four cards to an A4 page (2026-10-18, by request); each card carries
     the university name instead of the page letterhead. --}}
@section('no_letterhead', '1')

@section('content')
    <style>
        .cards-page {
            display: grid; grid-template-columns: 1fr 1fr; grid-template-rows: 1fr 1fr;
            gap: 6mm; height: 265mm; break-after: page; page-break-after: always;
        }
        .cards-page:last-child { break-after: auto; page-break-after: auto; }
        .cards-page > div { min-height: 0; overflow: hidden; break-inside: avoid; }
        @media screen { .cards-page { max-width: 210mm; margin: 0 auto 16px; } }
    </style>
    @forelse ($doctors->chunk(4) as $page)
        <div class="cards-page">
            @foreach ($page as [$doctor, $qr])
                <div>@include('print.partials.doctor-card', ['compact' => true])</div>
            @endforeach
        </div>
    @empty
        <p style="text-align:center">لا يوجد أطباء.</p>
    @endforelse
@endsection
