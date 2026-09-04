<?php

namespace App\Models;

use App\Traits\LogsActivity;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class Doctor extends Authenticatable
{
    // Notifiable brings routeNotificationFor()/notify(), needed both for
    // password-reset links and the mail notifications added alongside them.
    // Illuminate\Foundation\Auth\User already supplies CanResetPassword.
    use HasApiTokens, LogsActivity, Notifiable;

    public $timestamps = false;

    protected $fillable = [
        'name',
        'username',
        'password',
        'phone',
        'education_type_id',
        'stage_id',
        'academic_session_id',
        'profile_image',
        'email',
        'nfc_tag_id',
        'locale',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'created_at' => 'datetime',
        ];
    }

    public function educationType(): BelongsTo
    {
        return $this->belongsTo(EducationType::class);
    }

    public function stage(): BelongsTo
    {
        return $this->belongsTo(Stage::class);
    }

    public function academicSession(): BelongsTo
    {
        return $this->belongsTo(AcademicSession::class);
    }

    /**
     * The original enforces "one group at a time" by deleting every prior
     * membership on each add — which erases last year's group when a doctor
     * is enrolled in a new one. Here the pivot carries
     * `academic_session_id`, so the rule is **one group per session** and a
     * doctor keeps a group in each year they attended (see
     * GroupController::addDoctors and the 2026_08_19_120000 migration).
     */
    public function groups(): BelongsToMany
    {
        return $this->belongsToMany(Group::class, 'doctor_group_members')
            ->withPivot('added_at', 'academic_session_id');
    }

    public function taskInstances(): HasMany
    {
        return $this->hasMany(TaskInstance::class);
    }
}
