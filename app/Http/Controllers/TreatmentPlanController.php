<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Concerns\RendersSatelliteForm;
use App\Models\{TreatmentPlan};
use App\Support\CaseSheetReturn;
use App\Support\SurgerySatelliteForms;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Treatment Plan — one of the small satellite records attached to a parent case
 * sheet rather than a standalone sheet of its own. Layout in
 * App\Support\SurgerySatelliteForms.
 */
class TreatmentPlanController extends Controller
{
    use RendersSatelliteForm;

    private function sections(): array
    {
        return SurgerySatelliteForms::treatmentPlan();
    }

    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'treatment-plans',
            'title' => 'Treatment Plans',
            'titleField' => 'id',
            'records' => TreatmentPlan::with('dentalChart')->latest('id')->paginate(15),
        ]);
    }

    public function create(): Response
    {
        return $this->renderSatelliteForm('treatment-plans', 'Treatment Plan', $this->sections(), null);
    }

    public function edit(TreatmentPlan $record): Response
    {
        return $this->renderSatelliteForm('treatment-plans', 'Treatment Plan', $this->sections(), $record);
    }

    public function show(TreatmentPlan $record): Response
    {
        return $this->renderSatelliteForm('treatment-plans', 'Treatment Plan', $this->sections(), $record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        TreatmentPlan::create($this->satelliteValidate($request, $this->sections(), ['chart_id' => ['required', 'exists:dental_charts,id']]));

        return CaseSheetReturn::redirect()->with('success', 'Treatment plan created.');
    }

    public function update(Request $request, TreatmentPlan $record): RedirectResponse
    {
        $record->update($this->satelliteValidate($request, $this->sections(), ['chart_id' => ['required', 'exists:dental_charts,id']]));

        return CaseSheetReturn::redirect()->with('success', 'Treatment plan updated.');
    }

    public function destroy(TreatmentPlan $record): RedirectResponse
    {
        $record->delete();

        return CaseSheetReturn::redirect()->with('success', 'Treatment plan deleted.');
    }
}
