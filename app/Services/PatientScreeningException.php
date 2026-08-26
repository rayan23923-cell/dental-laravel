<?php

namespace App\Services;

use RuntimeException;

/** Thrown by `PatientScreeningGate::ensureClear()` — never a framework/DB error. */
class PatientScreeningException extends RuntimeException
{
}
