<?php

namespace App\Http\Requests;

class SubmitLoanApplicationRequest extends BaseFormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'loan_product_id' => 'required|exists:loan_products,id',
            'loan_product_term_id' => 'required|exists:loan_product_terms,id',
            'institution_id' => 'required|exists:institutions,id',
            'amount' => 'required|numeric|min:1',
            'reason' => 'required|string|max:255',
        ];
    }
}
