@extends('print.layout')

@section('title', 'بطاقات الأطباء')

@section('content')
    @forelse ($doctors as [$doctor, $qr])
        <div style="break-inside:avoid; page-break-inside:avoid;">
            @include('print.partials.doctor-card')
        </div>
    @empty
        <p style="text-align:center">لا يوجد أطباء.</p>
    @endforelse
@endsection
