<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Wi-Fi connectivity checks on the offline network (2026-10-12).
        $middleware->prepend(\App\Http\Middleware\AnswerConnectivityChecks::class);

        $middleware->web(append: [
            \App\Http\Middleware\EnsureOfflineActivated::class,
            // Must run before HandleInertiaRequests — that middleware
            // shares app()->getLocale() with the frontend and needs the
            // final resolved value.
            \App\Http\Middleware\ResolveLocale::class,
            \App\Http\Middleware\HandleInertiaRequests::class,
            \Illuminate\Http\Middleware\AddLinkHeadersForPreloadedAssets::class,
        ]);

        $middleware->api(append: [\App\Http\Middleware\EnsureOfflineActivated::class]);

        $middleware->alias([
            'role' => \App\Http\Middleware\EnsureUserHasRole::class,
            'permission' => \App\Http\Middleware\EnsureUserHasPermission::class,
            'case-sheet' => \App\Http\Middleware\EnforceCaseSheetAccess::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
