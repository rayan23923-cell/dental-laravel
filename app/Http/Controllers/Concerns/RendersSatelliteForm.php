<?php

namespace App\Http\Controllers\Concerns;

use App\Models\DentalChart;
use App\Models\Surgery;
use App\Models\ToothTreatment;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Shared rendering/validation for the small satellite sheets (surgery
 * follow-ups / images / medications, treatment plans / materials). They all
 * hang off a parent record rather than a doctor, so the doctor selector is
 * hidden and the parent picker is a `lookup` field fed from here.
 */
trait RendersSatelliteForm
{
    protected function renderSatelliteForm(
        string $resource,
        string $title,
        array $sections,
        $record,
        bool $readonly = false,
        array $extraProps = [],
    ): Response {
        return Inertia::render('Specialty/SectionedForm', [
            'resource' => $resource,
            'title' => $title,
            'sections' => $sections,
            'record' => $record,
            'readonly' => $readonly,
            'hideDoctor' => true,
            'lookups' => $this->satelliteLookups($sections),
            ...$extraProps,
        ]);
    }

    /** Option lists for whichever parent picker(s) the layout declares. */
    protected function satelliteLookups(array $sections): array
    {
        $keys = collect($sections)
            ->flatMap(fn ($s) => collect($s['fields'])->where('type', 'lookup')->pluck('key'))
            ->all();

        $lookups = [];

        if (in_array('surgery_id', $keys, true)) {
            $lookups['surgery_id'] = Surgery::latest('id')->limit(200)->get()
                ->map(fn ($s) => [
                    'id' => $s->id,
                    'label' => trim(sprintf(
                        '#%d — %s%s',
                        $s->id,
                        $s->patient_name ?: 'Unnamed patient',
                        $s->surgery_date_field ? ' · '.$s->surgery_date_field->format('Y-m-d') : ''
                    )),
                ])->all();
        }

        if (in_array('chart_id', $keys, true)) {
            $lookups['chart_id'] = DentalChart::latest('id')->limit(200)->get()
                ->map(fn ($c) => ['id' => $c->id, 'label' => sprintf('#%d — %s', $c->id, $c->patient_id ?: 'Unnamed patient')])
                ->all();
        }

        if (in_array('tooth_treatment_id', $keys, true)) {
            $lookups['tooth_treatment_id'] = ToothTreatment::latest('id')->limit(200)->get()
                ->map(fn ($t) => ['id' => $t->id, 'label' => sprintf('#%d — tooth %s', $t->id, $t->tooth_number ?? '?')])
                ->all();
        }

        return $lookups;
    }

    /** Validation rules derived from the layout's own field types. */
    protected function satelliteRules(array $sections, array $overrides = []): array
    {
        $rules = $overrides;

        foreach ($sections as $section) {
            foreach ($section['fields'] as $field) {
                if (isset($rules[$field['key']])) {
                    continue;
                }
                $rules[$field['key']] = match ($field['type']) {
                    'boolean' => ['nullable', 'boolean'],
                    'number' => ['nullable', 'integer'],
                    'decimal' => ['nullable', 'numeric'],
                    'date' => ['nullable', 'date'],
                    'file' => ['nullable', 'image', 'max:5120'],
                    'lookup' => ['nullable', 'integer'],
                    default => ['nullable', 'string'],
                };
            }
        }

        return $rules;
    }

    protected function satelliteValidate(Request $request, array $sections, array $overrides = []): array
    {
        return $request->validate($this->satelliteRules($sections, $overrides));
    }
}
