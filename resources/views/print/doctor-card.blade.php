@extends('print.layout')

@section('title', 'بطاقة الطبيب — ' . $doctor->name)

@section('content')
    @include('print.partials.doctor-card')
@endsection
