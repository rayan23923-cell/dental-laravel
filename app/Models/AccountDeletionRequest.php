<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** See the create_account_deletion_requests migration. */
class AccountDeletionRequest extends Model
{
    protected $fillable = ['account_type', 'account_id', 'identifier', 'contact', 'reason', 'source', 'status'];
}
