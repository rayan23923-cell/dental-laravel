<?php

namespace App\Console\Commands;

use App\Services\DefaultGroups;
use Illuminate\Console\Command;

/** Ensures group A for every stage and adds each stage's ungrouped doctors to it. */
class SyncDefaultGroups extends Command
{
    protected $signature = 'groups:sync-default';

    protected $description = 'Create group A for every stage and add ungrouped doctors to it';

    public function handle(): int
    {
        $added = DefaultGroups::sync();
        $this->info("Doctors added to group A: {$added}");

        return self::SUCCESS;
    }
}
