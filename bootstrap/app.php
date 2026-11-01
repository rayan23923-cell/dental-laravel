<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        // The licensing portal goes first so that, on its own domain, its
        // /login and / win over the clinic's routes of the same path.
        web: [__DIR__.'/../routes/licensing.php', __DIR__.'/../routes/web.php'],
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Wi-Fi connectivity checks on the offline network (2026-10-12).
        $middleware->prepend(\App\Http\Middleware\AnswerConnectivityChecks::class);
        $middleware->append(\App\Http\Middleware\SecurityHeaders::class);
        // Offline server opened by IP: logo/upload links on that IP too (2026-11-01).
        $middleware->prepend(\App\Http\Middleware\UseRequestHostForFilesOnIp::class);

        $middleware->web(append: [
            \App\Http\Middleware\EnsureOfflineActivated::class,
            \App\Http\Middleware\LogoutInactiveUsers::class,
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
            'licensing.auth' => \App\Http\Middleware\EnsureLicenseAdmin::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Errors during an in-app (Inertia) visit open our own error page
        // (2026-11-01, by request) instead of the framework's page in a
        // pop-up. Full page loads get resources/views/errors/page.blade.php.
        $exceptions->respond(function (\Symfony\Component\HttpFoundation\Response $response, \Throwable $e, \Illuminate\Http\Request $request) {
            $status = $response->getStatusCode();

            if ($request->header('X-Inertia') && ! config('app.debug') && in_array($status, [403, 404, 405, 419, 429, 500, 503], true)) {
                return \Inertia\Inertia::render('Error', ['status' => $status])
                    ->toResponse($request)
                    ->setStatusCode($status);
            }

            return $response;
        });
    })->create();
