<?php

use App\Http\Controllers\Licensing\AccountController;
use App\Http\Controllers\Licensing\AuthController;
use App\Http\Controllers\Licensing\CodeController;
use App\Http\Controllers\Licensing\UniversityController;
use Illuminate\Support\Facades\Route;

/*
| The licensing portal (2026-10-17, by request): its own site and accounts
| (the `license` guard) for universities, their activation codes and the
| computers using them. Hosted system only, never in an offline copy; served
| at the root of LICENSING_DOMAIN when set, else under /licensing.
*/

if (config('offline.edition')) {
    return;
}

$domain = config('offline.portal_domain');

($domain ? Route::domain($domain) : Route::prefix('licensing'))->name('licensing.')->group(function () {
    Route::get('/login', [AuthController::class, 'show'])->name('login');
    Route::post('/login', [AuthController::class, 'store'])->middleware('throttle:10,1')->name('login.store');

    Route::middleware('licensing.auth')->group(function () {
        Route::post('/logout', [AuthController::class, 'destroy'])->name('logout');

        Route::get('/', [UniversityController::class, 'index'])->name('home');
        Route::post('/universities', [UniversityController::class, 'store'])->name('universities.store');
        Route::get('/universities/{university}', [UniversityController::class, 'show'])->name('universities.show');
        Route::patch('/universities/{university}', [UniversityController::class, 'update'])->name('universities.update');
        Route::delete('/universities/{university}', [UniversityController::class, 'destroy'])->name('universities.destroy');

        Route::post('/universities/{university}/codes', [CodeController::class, 'store'])->name('codes.store');
        Route::patch('/codes/{license}', [CodeController::class, 'update'])->name('codes.update');
        Route::delete('/codes/{license}', [CodeController::class, 'destroy'])->name('codes.destroy');

        Route::get('/account', [AccountController::class, 'edit'])->name('account');
        Route::put('/account', [AccountController::class, 'update'])->name('account.update');
    });
});
