<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\SubmitLoanApplicationRequest;
use App\Http\Requests\UpdateLoanApplicationStatusRequest;
use App\Models\Institution;
use App\Models\Loan;
use App\Models\LoanApplication;
use App\Models\LoanProduct;
use App\Models\LoanProductTerm;
use App\Models\Transaction;
use App\Models\User;
use App\Services\AirtelDisbursementService;
use App\Services\AirtelService;
use App\Services\MtnMomoService;
use Exception;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class LoanApplicationController extends Controller
{
    public function getLoanBalance(User $user)
    {
        if ($user->id !== Auth::id()) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthorized.'
            ], 403);
        }

        return response()->json([
            'success' => true,
            'message' => 'Loan balance retrieved successfully',
            'outstandingAmount' => $user->outstandingAmount(),
        ]);
    }

    public function index($id)
    {
        if ((int) $id !== Auth::id()) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthorized.'
            ], 403);
        }

        try {
            $applications = LoanApplication::where('user_id', $id)->with(['user', 'loanProduct', 'loanProductTerm', 'institution', 'loan'])->latest()->get()->each(function ($application) {
                if ($application->loan) {
                    $application->loan->append('outstanding_balance');
                }
            });
            return response()->json(['data' => $applications], 200);
        } catch (Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    public function store(SubmitLoanApplicationRequest $request)
    {
        $user = Auth::user();

        if ($user->nin_status !== 'VALID') {
            return response()->json([
                'success' => false,
                'message' => 'Your NIN is not verified. Please head to the profile page to validate your NIN'
            ], 400);
        }

        try {
            $userId = $user->id;

            $unclearedLoan = Loan::where('user_id', $userId)
                ->whereNotIn('status', ['Cleared'])
                ->first();

            if ($unclearedLoan) {
                return response()->json([
                    'success' => false,
                    'message' => 'You have an uncleared loan, please clear that first to be able to qualify for another loan.'
                ], 400);
            }

            $pendingApplication = LoanApplication::where('user_id', $userId)
                ->where('status', 'Pending')
                ->first();

            if ($pendingApplication) {
                return response()->json([
                    'success' => false,
                    'message' => 'You already have a pending application, please wait for it to get processed.'
                ], 400);
            }

            $loanApplication = LoanApplication::create([
                'user_id' => $userId,
                'loan_product_id' => $request->loan_product_id,
                'loan_product_term_id' => $request->loan_product_term_id,
                'institution_id' => $request->institution_id,
                'amount' => $request->amount,
                'status' => 'Pending',
                'reason' => $request->reason,
            ]);
            $this->createTransaction($loanApplication);

            return response()->json([
                'success' => true,
                'message' => 'Application submitted successfully.',
                'data' => $loanApplication
            ], 201);
        } catch (\Exception $e) {
            Log::error('Error creating loan application: ' . $e->getMessage());
            return response()->json([
                'success' => false,
                'message' => 'Error creating loan application. ' . $e->getMessage(),
                'error' => $e->getMessage()
            ], 500);
        }
    }

    public function updateStatus(UpdateLoanApplicationStatusRequest $request, $id)
    {
        DB::beginTransaction();

        try {
            $loanApplication = LoanApplication::findOrFail($id);

            if ($loanApplication->status !== 'Pending') {
                return response()->json(['error' => 'Loan application is not in a pending state.'], 400);
            }

            $loanApplication->status = $request->status;

            if ($request->status === 'Approved') {
                $loanApplication->approved_at = now();
            } elseif ($request->status === 'Rejected') {
                $loanApplication->rejected_at = now();
            } elseif ($request->status === 'Disbursed') {
                $loanApplication->disbursed_at = now();
            } elseif ($request->status === 'Cancelled') {
                $loanApplication->cancelled_at = now();
            }

            $loanApplication->save();
            DB::commit();
            return response()->json(['data' => $loanApplication], 200);
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error updating loan application status: ' . $e->getMessage());
            return response()->json(['error' => 'An error occurred while updating the loan application status.'], 500);
        }
    }

    public function getProducts()
    {
        try {
            $user = Auth::user();
            $products = LoanProduct::with('institution')->where(function ($query) use ($user) {
                $query->where('institution_id', $user->institution_id)
                    ->orWhere('institution_id', null);
            })->get();

            return response()->json(['data' => $products], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    public function getProductTerms($id)
    {
        try {
            $terms = LoanProductTerm::with('product.institution')->where('loan_product_id', $id)->get();
            return response()->json(['data' => $terms], 200);
        } catch (Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    public function getInstitutions()
    {
        try {
            $institutions = Institution::all();
            return response()->json(['data' => $institutions], 200);
        } catch (Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    public function createTransaction(LoanApplication $loanApplication)
    {
        $transaction = Transaction::create([
            'user_id' => $loanApplication->user_id,
            'institution_id' => $loanApplication->institution_id,
            'loan_application_id' => $loanApplication->id,
            'loan_id' => null,
            'type' => 'Disbursement',
            'amount' => $loanApplication->amount,
            'phone' => $loanApplication->user->phone,
            'reference' => Str::uuid()->toString(),
            'status' => 'Pending',
        ]);
        $this->disburseLoan($loanApplication, $transaction);
    }

    public function disburseLoan(LoanApplication $loanApplication, Transaction $transaction)
    {
        try {
            $transaction->update([
                'status' => 'Processing',
                'processing_at' => now()
            ]);
            $channel = $transaction->network;
            if ($channel === 'AIRTEL') {
                $airtelService = new AirtelDisbursementService(new AirtelService());
                $paymentResponse = $airtelService->disburse($transaction);
            } else if ($channel === 'MTN') {
                $mtnService = new MtnMomoService();
                $paymentResponse = $mtnService->disburse($transaction->phone, $transaction->amount, $transaction->reference, 'Loan Disbursement');
            } else {
                throw new \Exception("Unsupported payment gateway: {$channel}");
            }
            if (!$paymentResponse['success']) {
                throw new \Exception($paymentResponse['message'] ?? 'Payment processing failed');
            }

            $transaction->update([
                'status' => $paymentResponse['status'],
                'external_reference' => $paymentResponse['transaction_id'],
                'updated_at' => now(),
            ]);
        } catch (\Exception $e) {
            Log::error('Loan Disbursement failed', [
                'error' => $e->getMessage(),
                'loan_id' => $loanApplication->id,
                'transaction_id' => $transaction->id,
            ]);

            $transaction->update(['status' => 'FAILED']);

            $transaction->loanApplication->update([
                'status' => 'Rejected',
                'rejected_at' => now(),
            ]);

            return [
                'success' => false,
                'error' => $e->getMessage(),
                'transaction' => $transaction,
                'loan_application' => $loanApplication->fresh()
            ];
        }
    }
}
