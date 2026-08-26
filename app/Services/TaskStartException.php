<?php

namespace App\Services;

use RuntimeException;

/** Thrown by `TaskStarter::start()` for its business-rule refusals — never a framework/DB error. */
class TaskStartException extends RuntimeException
{
}
