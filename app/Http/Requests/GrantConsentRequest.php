<?php

namespace App\Http\Requests;

class GrantConsentRequest extends BaseFormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'purpose' => 'required|string|max:64',
            'policy_version' => 'required|string|max:32',
            'channel' => 'nullable|string|max:32',
            'metadata' => 'nullable|array',
        ];
    }
}
