<?php

namespace App\Http\Requests;

class GenerateOtpRequest extends BaseFormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'phone' => 'required|string',
        ];
    }
}
