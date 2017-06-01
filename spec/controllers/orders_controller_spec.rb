require 'rails_helper'

RSpec.describe OrdersController, type: :controller do
  def setup_user
    @request.env['devise.mapping'] = Devise.mappings[:user]
    groups = ["cowboys"]
    user = create(:user)
    sign_in user
    return user
  end

  describe "#show" do
    context "when the order belongs to the current user" do
      it "should work" do
        user = setup_user
        @wo = create(:work_order, user_id: user.id)

        get :show, params: { work_order_id: @wo.id, id: 'set' }

        expect(response).to have_http_status(:ok)
        expect(response.redirect_url).to be_nil
        expect(flash[:alert]).to be_nil
      end
    end

    context "when the order belongs to another user" do
      it "should fail authorisation" do
        user = setup_user
        user2 = create(:user, email: 'dirk@sanger.ac.uk')
        @wo = create(:work_order, user_id: user2.id)

        get :show, params: { work_order_id: @wo.id, id: 'set' }

        expect(response).to have_http_status(:found)
        expect(response.redirect_url).to be_present
        expect(flash[:alert]).to match(/not authori[sz]ed/)
      end
    end
  end

  describe "#update" do
    context "when the step succeeds" do
      before do
        user = setup_user
        @wo = create(:work_order, user_id: user.id)
        allow(WorkOrder).to receive(:find).and_return(@wo)
        @uos = double('UpdateOrderService')
        allow(UpdateOrderService).to receive(:new).and_return(@uos)
        allow(@uos).to receive(:perform).and_return(true)
        allow(@wo).to receive(:save).and_return(true)

        wop = { original_set_uuid: 'bananas' }
        put :update, params: { work_order_id: @wo.id, id: 'set', work_order: wop }
      end

      it "should save the work order (via render_wizard)" do
        # When the step succeeds, render_wizard work_order is called, which tries to save the order
        expect(@wo).to have_received(:save)
      end

      it "should have performed the step" do
        expect(UpdateOrderService).to have_received(:new).with(anything, @wo, flash)
        expect(@uos).to have_received(:perform).with(:set)
      end

      it "should go to the next step" do
        expect(response).to have_http_status(:found)
        expect(response.redirect_url).to eq work_order_build_url(
          id: 'product',
          work_order_id: @wo.id
        )
      end

      it "should not have an authorisation error" do
        expect(flash[:alert]).to be_nil
      end
    end

    context "when the step fails" do
      before do
        user = setup_user
        @wo = create(:work_order, user_id: user.id)
        allow(WorkOrder).to receive(:find).and_return(@wo)
        @uos = double('UpdateOrderService')
        allow(UpdateOrderService).to receive(:new).and_return(@uos)
        allow(@uos).to receive(:perform).and_return(false)
        allow(@wo).to receive(:save).and_return(true)

        wop = { original_set_uuid: 'bananas' }
        put :update, params: { work_order_id: @wo.id, id: 'set', work_order: wop }
      end

      it "should not save the work order (via render_wizard)" do
        # When the step succeeds, render_wizard is called, which does not try to save the order
        expect(@wo).not_to have_received(:save)
      end

      it "should have tried to perform the step" do
        expect(UpdateOrderService).to have_received(:new).with(anything, @wo, flash)
        expect(@uos).to have_received(:perform).with(:set)
      end

      it "should stay on the same step" do
        expect(response).to have_http_status(:ok)
        expect(response.redirect_url).to be_nil
      end

      it "should not have an authorisation error" do
        expect(flash[:alert]).to be_nil
      end
    end

    context "when the order belongs to another user" do
      it "should fail authorisation" do
        user = setup_user
        user2 = create(:user, email: 'dirk@sanger.ac.uk')
        @wo = create(:work_order, user_id: user2.id)

        expect(UpdateOrderService).not_to receive(:new)

        put :update, params: { work_order_id: @wo.id, id: 'set', work_order: {} }

        expect(response).to have_http_status(:found)
        expect(response.redirect_url).to be_present
        expect(flash[:alert]).to match(/not authori[sz]ed/)
      end
    end
  end

end