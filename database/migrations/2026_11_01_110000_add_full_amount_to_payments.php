<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The price at the time of payment (2026-11-01, by request): a receipt
 * printed at 10,000 keeps 10,000 (and its discount) after the service or
 * lab price changes to 15,000. `amount` was already stored; this keeps the
 * undiscounted price it was taken from, which used to be read from the
 * current price.
 *
 * Existing rows: a patient without a discount paid the full price, so
 * full_amount = amount; for discounted ones the current price is the best
 * record there is.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasColumn('payments', 'full_amount')) {
            return;
        }

        Schema::table('payments', function (Blueprint $table) {
            $table->decimal('full_amount', 12, 2)->nullable();
        });

        DB::table('payments')->update(['full_amount' => DB::raw('amount')]);

        if (! Schema::hasColumn('patients_simple', 'discount_eligible')) {
            return;
        }

        $eligible = DB::table('patients_simple')->where('discount_eligible', true)->pluck('service_id', 'id');
        if ($eligible->isEmpty()) {
            return;
        }

        $labFee = Schema::hasColumn('clinic_settings', 'lab_fee') ? DB::table('clinic_settings')->value('lab_fee') : null;
        $prices = DB::table('register_services')->pluck('price', 'id');

        DB::table('payments')->whereIn('patient_registration_id', $eligible->keys())->orderBy('id')
            ->each(function ($p) use ($eligible, $labFee, $prices) {
                $full = $p->type === 'lab' ? $labFee : ($prices[$eligible[$p->patient_registration_id]] ?? null);
                if ($full !== null && (float) $full >= (float) $p->amount) {
                    DB::table('payments')->where('id', $p->id)->update(['full_amount' => $full]);
                }
            });
    }

    public function down(): void
    {
        if (Schema::hasColumn('payments', 'full_amount')) {
            Schema::table('payments', fn (Blueprint $t) => $t->dropColumn('full_amount'));
        }
    }
};
