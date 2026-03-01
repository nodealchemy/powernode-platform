# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Invoices', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:subscription) { create(:subscription, account: account, plan: plan) }

  # User with billing.read permission only
  let(:billing_reader) do
    create(:user, account: account, permissions: [ 'billing.read' ])
  end

  # User with billing.manage permission
  let(:billing_manager) do
    create(:user, account: account, permissions: [ 'billing.read', 'billing.manage' ])
  end

  # User without billing permissions
  let(:regular_user) do
    create(:user, account: account, permissions: [])
  end

  # Another account for isolation tests
  let(:other_account) { create(:account) }
  let(:other_subscription) { create(:subscription, account: other_account, plan: plan) }

  before(:each) do
    Rails.cache.clear
  end

  describe 'GET /api/v1/invoices' do
    context 'with billing.read permission' do
      let!(:invoices) do
        # Create invoices with different statuses for the account
        [
          create(:invoice, account: account, subscription: subscription, status: 'draft'),
          create(:invoice, account: account, subscription: subscription, status: 'open'),
          create(:invoice, account: account, subscription: subscription, status: 'paid', paid_at: 1.day.ago)
        ]
      end

      let!(:other_invoice) do
        create(:invoice, account: other_account, subscription: other_subscription, status: 'draft')
      end

      it 'returns invoices for the current account' do
        get '/api/v1/invoices', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        data = json_response['data']

        expect(data.length).to eq(3)
        expect(data.map { |i| i['id'] }).to match_array(invoices.map(&:id))
        expect(data.map { |i| i['id'] }).not_to include(other_invoice.id)
      end

      it 'returns invoices ordered by created_at desc' do
        get '/api/v1/invoices', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        data = json_response['data']

        created_ats = data.map { |i| Time.parse(i['created_at']) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it 'returns invoice data with correct structure' do
        get '/api/v1/invoices', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        invoice_data = json_response['data'].first

        expect(invoice_data).to include(
          'id',
          'invoice_number',
          'status',
          'subtotal',
          'tax_amount',
          'total_amount',
          'currency',
          'due_date',
          'created_at',
          'updated_at'
        )
      end

      it 'includes subscription data when present' do
        get '/api/v1/invoices', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        invoice_data = json_response['data'].first

        expect(invoice_data['subscription']).to include(
          'id' => subscription.id,
          'plan_name' => plan.name
        )
      end
    end

    context 'pagination' do
      before do
        # Create 30 invoices for pagination tests
        30.times do
          create(:invoice, account: account, subscription: subscription)
        end
      end

      it 'returns paginated results with default per_page of 25' do
        get '/api/v1/invoices', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        expect(json_response['data'].length).to eq(25)
        expect(json_response['meta']['pagination']).to include(
          'current_page' => 1,
          'per_page' => 25,
          'total_pages' => 2,
          'total_count' => 30
        )
      end

      it 'respects page parameter' do
        get '/api/v1/invoices?page=2', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        expect(json_response['data'].length).to eq(5)
        expect(json_response['meta']['pagination']['current_page']).to eq(2)
      end

      it 'respects per_page parameter' do
        get '/api/v1/invoices?per_page=10', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        expect(json_response['data'].length).to eq(10)
        expect(json_response['meta']['pagination']['per_page']).to eq(10)
        expect(json_response['meta']['pagination']['total_pages']).to eq(3)
      end

      it 'caps per_page at 100' do
        get '/api/v1/invoices?per_page=200', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        expect(json_response['meta']['pagination']['per_page']).to eq(100)
      end
    end

    context 'without billing.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/invoices', headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: billing.read', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/invoices', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/invoices/:id' do
    let!(:invoice) { create(:invoice, account: account, subscription: subscription) }
    let!(:line_items) do
      [
        create(:invoice_line_item, invoice: invoice, description: 'Monthly subscription'),
        create(:invoice_line_item, :usage_item, invoice: invoice)
      ]
    end

    context 'with billing.read permission' do
      it 'returns the invoice with line items' do
        get "/api/v1/invoices/#{invoice.id}", headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        data = json_response['data']

        expect(data['id']).to eq(invoice.id)
        expect(data['invoice_number']).to eq(invoice.invoice_number)
        expect(data['line_items']).to be_an(Array)
        expect(data['line_items'].length).to eq(2)
      end

      it 'returns line item details' do
        get "/api/v1/invoices/#{invoice.id}", headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        line_item = json_response['data']['line_items'].first

        expect(line_item).to include(
          'id',
          'description',
          'quantity',
          'unit_price',
          'amount'
        )
      end
    end

    context 'with invoice from another account' do
      let(:other_invoice) { create(:invoice, account: other_account, subscription: other_subscription) }

      it 'returns not found error' do
        get "/api/v1/invoices/#{other_invoice.id}", headers: auth_headers_for(billing_reader), as: :json

        expect_error_response('Invoice not found', 404)
      end
    end

    context 'with non-existent invoice' do
      it 'returns not found error' do
        get '/api/v1/invoices/non-existent-id', headers: auth_headers_for(billing_reader), as: :json

        expect_error_response('Invoice not found', 404)
      end
    end

    context 'without billing.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/invoices/#{invoice.id}", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: billing.read', 403)
      end
    end
  end

  describe 'POST /api/v1/invoices/:id/send' do
    context 'with billing.manage permission' do
      context 'when invoice is in draft status' do
        let(:draft_invoice) { create(:invoice, account: account, subscription: subscription, status: 'draft') }

        it 'sends the invoice and updates status to open' do
          post "/api/v1/invoices/#{draft_invoice.id}/send", headers: auth_headers_for(billing_manager), as: :json

          expect_success_response
          expect(json_response['data']['status']).to eq('open')

          draft_invoice.reload
          expect(draft_invoice.status).to eq('open')
        end
      end

      context 'when invoice is already open' do
        let(:open_invoice) { create(:invoice, account: account, subscription: subscription, status: 'open') }

        it 'returns unprocessable error' do
          post "/api/v1/invoices/#{open_invoice.id}/send", headers: auth_headers_for(billing_manager), as: :json

          expect_error_response('Invoice has already been sent', 422)
        end
      end

      context 'when invoice is paid' do
        let(:paid_invoice) { create(:invoice, account: account, subscription: subscription, status: 'paid', paid_at: 1.day.ago) }

        it 'returns unprocessable error' do
          post "/api/v1/invoices/#{paid_invoice.id}/send", headers: auth_headers_for(billing_manager), as: :json

          expect_error_response('Invoice has already been sent', 422)
        end
      end
    end

    context 'without billing.manage permission' do
      let(:draft_invoice) { create(:invoice, account: account, subscription: subscription, status: 'draft') }

      it 'returns forbidden error for user with only billing.read' do
        post "/api/v1/invoices/#{draft_invoice.id}/send", headers: auth_headers_for(billing_reader), as: :json

        expect_error_response('Permission denied: billing.manage', 403)
      end

      it 'returns forbidden error for regular user' do
        post "/api/v1/invoices/#{draft_invoice.id}/send", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: billing.manage', 403)
      end
    end
  end

  describe 'POST /api/v1/invoices/:id/mark_paid' do
    context 'with billing.manage permission' do
      context 'when invoice is open' do
        let(:open_invoice) { create(:invoice, account: account, subscription: subscription, status: 'open') }

        it 'marks the invoice as paid' do
          post "/api/v1/invoices/#{open_invoice.id}/mark_paid", headers: auth_headers_for(billing_manager), as: :json

          expect_success_response
          expect(json_response['data']['status']).to eq('paid')

          open_invoice.reload
          expect(open_invoice.status).to eq('paid')
          expect(open_invoice.paid_at).to be_present
        end
      end

      context 'when invoice is overdue (open with past due date)' do
        let(:overdue_invoice) { create(:invoice, account: account, subscription: subscription, status: 'open', due_at: 5.days.ago) }

        it 'marks the invoice as paid' do
          post "/api/v1/invoices/#{overdue_invoice.id}/mark_paid", headers: auth_headers_for(billing_manager), as: :json

          expect_success_response
          expect(json_response['data']['status']).to eq('paid')
        end
      end

      context 'when invoice is in draft status' do
        let(:draft_invoice) { create(:invoice, account: account, subscription: subscription, status: 'draft') }

        it 'returns unprocessable error' do
          post "/api/v1/invoices/#{draft_invoice.id}/mark_paid", headers: auth_headers_for(billing_manager), as: :json

          expect_error_response("Invoice cannot be marked as paid (current status: draft)", 422)
        end
      end

      context 'when invoice is already paid' do
        let(:paid_invoice) { create(:invoice, account: account, subscription: subscription, status: 'paid', paid_at: 1.day.ago) }

        it 'returns unprocessable error' do
          post "/api/v1/invoices/#{paid_invoice.id}/mark_paid", headers: auth_headers_for(billing_manager), as: :json

          expect_error_response("Invoice cannot be marked as paid (current status: paid)", 422)
        end
      end

      context 'when invoice is void' do
        let(:void_invoice) { create(:invoice, account: account, subscription: subscription) }

        before do
          void_invoice.update_column(:status, 'void')
        end

        it 'returns unprocessable error' do
          post "/api/v1/invoices/#{void_invoice.id}/mark_paid", headers: auth_headers_for(billing_manager), as: :json

          expect_error_response("Invoice cannot be marked as paid (current status: void)", 422)
        end
      end
    end

    context 'without billing.manage permission' do
      let(:open_invoice) { create(:invoice, account: account, subscription: subscription, status: 'open') }

      it 'returns forbidden error' do
        post "/api/v1/invoices/#{open_invoice.id}/mark_paid", headers: auth_headers_for(billing_reader), as: :json

        expect_error_response('Permission denied: billing.manage', 403)
      end
    end
  end

  describe 'POST /api/v1/invoices/:id/void' do
    context 'with billing.manage permission' do
      context 'when invoice is in draft status' do
        let(:draft_invoice) { create(:invoice, account: account, subscription: subscription, status: 'draft') }

        it 'voids the invoice' do
          post "/api/v1/invoices/#{draft_invoice.id}/void",
               params: { reason: 'Customer request' },
               headers: auth_headers_for(billing_manager),
               as: :json

          expect_success_response
          expect(json_response['data']['status']).to eq('void')

          draft_invoice.reload
          expect(draft_invoice.status).to eq('void')
        end
      end

      context 'when invoice is open' do
        let(:open_invoice) { create(:invoice, account: account, subscription: subscription, status: 'open') }

        it 'voids the invoice' do
          post "/api/v1/invoices/#{open_invoice.id}/void", headers: auth_headers_for(billing_manager), as: :json

          expect_success_response
          expect(json_response['data']['status']).to eq('void')
        end
      end

      context 'when invoice is already paid' do
        let(:paid_invoice) { create(:invoice, account: account, subscription: subscription, status: 'paid', paid_at: 1.day.ago) }

        it 'returns unprocessable error' do
          post "/api/v1/invoices/#{paid_invoice.id}/void", headers: auth_headers_for(billing_manager), as: :json

          expect_error_response("Invoice cannot be voided (current status: paid)", 422)
        end
      end

      context 'when invoice is already void' do
        let(:void_invoice) { create(:invoice, account: account, subscription: subscription) }

        before do
          void_invoice.update_column(:status, 'void')
        end

        it 'returns unprocessable error' do
          post "/api/v1/invoices/#{void_invoice.id}/void", headers: auth_headers_for(billing_manager), as: :json

          expect_error_response("Invoice cannot be voided (current status: void)", 422)
        end
      end
    end

    context 'without billing.manage permission' do
      let(:draft_invoice) { create(:invoice, account: account, subscription: subscription, status: 'draft') }

      it 'returns forbidden error' do
        post "/api/v1/invoices/#{draft_invoice.id}/void", headers: auth_headers_for(billing_reader), as: :json

        expect_error_response('Permission denied: billing.manage', 403)
      end
    end
  end

  describe 'POST /api/v1/invoices/:id/retry_payment' do
    context 'with billing.manage permission' do
      context 'when invoice is open' do
        let(:open_invoice) { create(:invoice, account: account, subscription: subscription, status: 'open') }

        it 'initiates payment retry' do
          post "/api/v1/invoices/#{open_invoice.id}/retry_payment", headers: auth_headers_for(billing_manager), as: :json

          expect_success_response
        end
      end

      context 'when invoice is uncollectible' do
        let(:uncollectible_invoice) { create(:invoice, account: account, subscription: subscription, status: 'uncollectible') }

        it 'initiates payment retry' do
          post "/api/v1/invoices/#{uncollectible_invoice.id}/retry_payment", headers: auth_headers_for(billing_manager), as: :json

          expect_success_response
        end
      end

      context 'when invoice is in draft status' do
        let(:draft_invoice) { create(:invoice, account: account, subscription: subscription, status: 'draft') }

        it 'returns unprocessable error' do
          post "/api/v1/invoices/#{draft_invoice.id}/retry_payment", headers: auth_headers_for(billing_manager), as: :json

          expect_error_response('Invoice is not eligible for payment retry', 422)
        end
      end

      context 'when invoice is paid' do
        let(:paid_invoice) { create(:invoice, account: account, subscription: subscription, status: 'paid', paid_at: 1.day.ago) }

        it 'returns unprocessable error' do
          post "/api/v1/invoices/#{paid_invoice.id}/retry_payment", headers: auth_headers_for(billing_manager), as: :json

          expect_error_response('Invoice is not eligible for payment retry', 422)
        end
      end

      context 'when invoice is void' do
        let(:void_invoice) { create(:invoice, account: account, subscription: subscription) }

        before do
          void_invoice.update_column(:status, 'void')
        end

        it 'returns unprocessable error' do
          post "/api/v1/invoices/#{void_invoice.id}/retry_payment", headers: auth_headers_for(billing_manager), as: :json

          expect_error_response('Invoice is not eligible for payment retry', 422)
        end
      end
    end

    context 'without billing.manage permission' do
      let(:open_invoice) { create(:invoice, account: account, subscription: subscription, status: 'open') }

      it 'returns forbidden error' do
        post "/api/v1/invoices/#{open_invoice.id}/retry_payment", headers: auth_headers_for(billing_reader), as: :json

        expect_error_response('Permission denied: billing.manage', 403)
      end
    end
  end

  describe 'GET /api/v1/invoices/:id/pdf' do
    let(:invoice) { create(:invoice, account: account, subscription: subscription) }

    context 'with billing.read permission' do
      it 'returns PDF data' do
        get "/api/v1/invoices/#{invoice.id}/pdf", headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        data = json_response['data']

        expect(data['invoice_id']).to eq(invoice.id)
        expect(data['invoice_number']).to eq(invoice.invoice_number)
        expect(data['filename']).to eq("invoice_#{invoice.invoice_number}.pdf")
        expect(data['content_type']).to eq('application/pdf')
        expect(data['content']).to be_present
        expect(data['generated_at']).to be_present
      end

      it 'returns base64 encoded content' do
        get "/api/v1/invoices/#{invoice.id}/pdf", headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        content = json_response['data']['content']

        # Verify it's valid base64
        expect { Base64.strict_decode64(content) }.not_to raise_error
      end
    end

    context 'with invoice from another account' do
      let(:other_invoice) { create(:invoice, account: other_account, subscription: other_subscription) }

      it 'returns not found error' do
        get "/api/v1/invoices/#{other_invoice.id}/pdf", headers: auth_headers_for(billing_reader), as: :json

        expect_error_response('Invoice not found', 404)
      end
    end

    context 'without billing.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/invoices/#{invoice.id}/pdf", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: billing.read', 403)
      end
    end
  end

  describe 'GET /api/v1/invoices/statistics' do
    context 'with billing.read permission' do
      before do
        # Create invoices with various statuses and amounts
        create(:invoice, account: account, subscription: subscription, status: 'paid', paid_at: 1.day.ago, total_cents: 10000)
        create(:invoice, account: account, subscription: subscription, status: 'paid', paid_at: 2.days.ago, total_cents: 20000)
        create(:invoice, account: account, subscription: subscription, status: 'draft', total_cents: 5000)

        # Open invoice (pending)
        create(:invoice, account: account, subscription: subscription, status: 'open', total_cents: 15000)

        # Overdue invoice (open with past due_at)
        create(:invoice, account: account, subscription: subscription, status: 'open', total_cents: 8000, due_at: 5.days.ago)
      end

      it 'returns summary statistics' do
        get '/api/v1/invoices/statistics', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        summary = json_response['data']['summary']

        expect(summary['total_invoices']).to eq(5)
        expect(summary['total_amount']).to be_present
        expect(summary['paid_amount']).to be_present
        expect(summary['pending_amount']).to be_present
        expect(summary['overdue_amount']).to be_present
        expect(summary['average_invoice_amount']).to be_present
      end

      it 'returns status breakdown' do
        get '/api/v1/invoices/statistics', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        by_status = json_response['data']['by_status']

        expect(by_status).to be_a(Hash)
        expect(by_status['paid']).to eq(2)
        expect(by_status['draft']).to eq(1)
        expect(by_status['open']).to eq(2)
      end

      it 'returns status amount breakdown' do
        get '/api/v1/invoices/statistics', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        by_status_amount = json_response['data']['by_status_amount']

        expect(by_status_amount).to be_a(Hash)
      end

      it 'returns payment rate' do
        get '/api/v1/invoices/statistics', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        payment_rate = json_response['data']['payment_rate']

        expect(payment_rate).to be_a(Numeric)
        expect(payment_rate).to be >= 0
        expect(payment_rate).to be <= 100
      end

      it 'returns overdue invoice count' do
        get '/api/v1/invoices/statistics', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        expect(json_response['data']['overdue_invoices']).to eq(1)
      end

      it 'returns currency breakdown' do
        get '/api/v1/invoices/statistics', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        currency_breakdown = json_response['data']['currency_breakdown']

        expect(currency_breakdown).to be_a(Hash)
        expect(currency_breakdown).to have_key('USD')
      end
    end

    context 'with date filtering' do
      before do
        # Create invoices at different times
        travel_to 2.months.ago do
          create(:invoice, account: account, subscription: subscription, status: 'paid', paid_at: Time.current, total_cents: 5000)
        end

        travel_to 1.week.ago do
          create(:invoice, account: account, subscription: subscription, status: 'paid', paid_at: Time.current, total_cents: 10000)
        end

        create(:invoice, account: account, subscription: subscription, status: 'draft', total_cents: 7500)
      end

      it 'filters by start_date' do
        start_date = 1.month.ago.to_date.iso8601
        get "/api/v1/invoices/statistics?start_date=#{start_date}",
            headers: auth_headers_for(billing_reader),
            as: :json

        expect_success_response
        # Should only include invoices from last month
        expect(json_response['data']['summary']['total_invoices']).to eq(2)
      end

      it 'filters by end_date' do
        end_date = 1.month.ago.to_date.iso8601
        get "/api/v1/invoices/statistics?end_date=#{end_date}",
            headers: auth_headers_for(billing_reader),
            as: :json

        expect_success_response
        # Should only include invoices from 2+ months ago
        expect(json_response['data']['summary']['total_invoices']).to eq(1)
      end

      it 'filters by date range' do
        start_date = 3.months.ago.to_date.iso8601
        end_date = 1.month.ago.to_date.iso8601
        get "/api/v1/invoices/statistics?start_date=#{start_date}&end_date=#{end_date}",
            headers: auth_headers_for(billing_reader),
            as: :json

        expect_success_response
        expect(json_response['data']['summary']['total_invoices']).to eq(1)
      end
    end

    context 'with no invoices' do
      it 'returns zero statistics' do
        get '/api/v1/invoices/statistics', headers: auth_headers_for(billing_reader), as: :json

        expect_success_response
        summary = json_response['data']['summary']

        expect(summary['total_invoices']).to eq(0)
        expect(summary['total_amount']).to eq(0)
        expect(summary['average_invoice_amount']).to eq(0)
        expect(json_response['data']['payment_rate']).to eq(0)
      end
    end

    context 'without billing.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/invoices/statistics', headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: billing.read', 403)
      end
    end
  end

  describe 'invoice lifecycle transitions' do
    let(:invoice) { create(:invoice, account: account, subscription: subscription, status: 'draft') }

    context 'draft -> open -> paid lifecycle' do
      it 'completes the full payment lifecycle' do
        # Step 1: Send the invoice (transitions to open)
        post "/api/v1/invoices/#{invoice.id}/send", headers: auth_headers_for(billing_manager), as: :json
        expect_success_response
        expect(json_response['data']['status']).to eq('open')

        # Step 2: Mark as paid
        post "/api/v1/invoices/#{invoice.id}/mark_paid", headers: auth_headers_for(billing_manager), as: :json
        expect_success_response
        expect(json_response['data']['status']).to eq('paid')

        invoice.reload
        expect(invoice.status).to eq('paid')
        expect(invoice.paid_at).to be_present
      end
    end

    context 'draft -> void lifecycle' do
      it 'allows voiding a draft invoice' do
        post "/api/v1/invoices/#{invoice.id}/void",
             params: { reason: 'Cancelled order' },
             headers: auth_headers_for(billing_manager),
             as: :json

        expect_success_response
        expect(json_response['data']['status']).to eq('void')

        invoice.reload
        expect(invoice.status).to eq('void')
      end
    end

    context 'draft -> open -> void lifecycle' do
      it 'allows voiding an open invoice' do
        # Send the invoice (transitions to open)
        post "/api/v1/invoices/#{invoice.id}/send", headers: auth_headers_for(billing_manager), as: :json
        expect_success_response

        # Void the invoice
        post "/api/v1/invoices/#{invoice.id}/void",
             params: { reason: 'Customer dispute' },
             headers: auth_headers_for(billing_manager),
             as: :json

        expect_success_response
        expect(json_response['data']['status']).to eq('void')
      end
    end

    context 'invalid transitions' do
      it 'prevents paying a draft invoice directly' do
        post "/api/v1/invoices/#{invoice.id}/mark_paid", headers: auth_headers_for(billing_manager), as: :json

        expect_error_response("Invoice cannot be marked as paid (current status: draft)", 422)
      end

      it 'prevents voiding a paid invoice' do
        # First complete the lifecycle
        post "/api/v1/invoices/#{invoice.id}/send", headers: auth_headers_for(billing_manager), as: :json
        post "/api/v1/invoices/#{invoice.id}/mark_paid", headers: auth_headers_for(billing_manager), as: :json

        # Try to void
        post "/api/v1/invoices/#{invoice.id}/void", headers: auth_headers_for(billing_manager), as: :json

        expect_error_response("Invoice cannot be voided (current status: paid)", 422)
      end

      it 'prevents retrying payment on draft invoice' do
        post "/api/v1/invoices/#{invoice.id}/retry_payment", headers: auth_headers_for(billing_manager), as: :json

        expect_error_response('Invoice is not eligible for payment retry', 422)
      end

      it 'prevents retrying payment on paid invoice' do
        invoice.update_column(:status, 'paid')

        post "/api/v1/invoices/#{invoice.id}/retry_payment", headers: auth_headers_for(billing_manager), as: :json

        expect_error_response('Invoice is not eligible for payment retry', 422)
      end
    end
  end

  describe 'account isolation' do
    let!(:account_invoice) { create(:invoice, account: account, subscription: subscription) }
    let!(:other_invoice) { create(:invoice, account: other_account, subscription: other_subscription) }

    it 'only returns invoices for the authenticated user account' do
      get '/api/v1/invoices', headers: auth_headers_for(billing_reader), as: :json

      expect_success_response
      invoice_ids = json_response['data'].map { |i| i['id'] }

      expect(invoice_ids).to include(account_invoice.id)
      expect(invoice_ids).not_to include(other_invoice.id)
    end

    it 'prevents accessing another account invoice directly' do
      get "/api/v1/invoices/#{other_invoice.id}", headers: auth_headers_for(billing_reader), as: :json

      expect_error_response('Invoice not found', 404)
    end

    it 'prevents modifying another account invoice' do
      post "/api/v1/invoices/#{other_invoice.id}/void", headers: auth_headers_for(billing_manager), as: :json

      expect_error_response('Invoice not found', 404)
    end
  end
end
