<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Concerns\RendersSatelliteForm;
use App\Models\{SurgeryFollowUp};
use App\Support\SurgerySatelliteForms;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Surgery Follow-Up — one of the small satellite records attached to a parent case
 * sheet rather than a standalone sheet of its own. Layout in
 * App\Support\SurgerySatelliteForms.
 */
class SurgeryFollowUpController extends Controller
{
    use RendersSatelliteForm;

    private function sections(): array
    {
        return SurgerySatelliteForms::followUp();
    }

    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'surgery-follow-ups',
            'title' => 'Surgery Follow-Ups',
            'titleField' => 'id',
            'records' => SurgeryFollowUp::with('surgery')->latest('id')->paginate(15),
        ]);
    }

    public function create(): Response
    {
        return $this->renderSatelliteForm('surgery-follow-ups', 'Surgery Follow-Up', $this->sections(), null);
    }

    public function edit(SurgeryFollowUp $record): Response
    {
        return $this->renderSatelliteForm('surgery-follow-ups', 'Surgery Follow-Up', $this->sections(), $record);
    }

    public function show(SurgeryFollowUp $record): Response
    {
        return $this->renderSatelliteForm('surgery-follow-ups', 'Surgery Follow-Up', $this->sections(), $record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        SurgeryFollowUp::create($this->satelliteValidate($request, $this->sections(), ['surgery_id' => ['required', 'exists:surgeries,id']]));

        return redirect()->route('surgery-follow-ups.index')->with('success', 'Surgery follow-up created.');
    }

    public function update(Request $request, SurgeryFollowUp $record): RedirectResponse
    {
        $record->update($this->satelliteValidate($request, $this->sections(), ['surgery_id' => ['required', 'exists:surgeries,id']]));

        return redirect()->route('surgery-follow-ups.index')->with('success', 'Surgery follow-up updated.');
    }

    public function destroy(SurgeryFollowUp $record): RedirectResponse
    {
        $record->delete();

        return redirect()->route('surgery-follow-ups.index')->with('success', 'Surgery follow-up deleted.');
    }
}
