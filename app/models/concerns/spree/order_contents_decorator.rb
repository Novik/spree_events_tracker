module Spree
  module OrderContentsWithTracker

    # Override: since order's line_items were overridden
    def update_cart(params)
      if order.update_attributes(filter_order_items(params))
        order.line_items.select(&:changed?).each do |line_item|
          if line_item.previous_changes.keys.include?('quantity')
            Spree::Cart::Event::Tracker.new(
              actor: order, target: line_item, total: order.total, variant_id: line_item.variant_id
            ).track
          end
        end
        # line_items which have 0 quantity will be lost and couldn't be tracked
        # so tracking is done before the execution of next statement
        order.line_items = order.line_items.select { |li| li.quantity > 0 }
        # Update totals, then check if the order is eligible for any cart promotions.
        # If we do not update first, then the item total will be wrong and ItemTotal
        # promotion rules would not be triggered.
        reload_totals
        PromotionHandler::Cart.new(order).activate
        order.ensure_updated_shipments
        reload_totals
        true
      else
        false
      end
    end

    def remove(variant, quantity = 1, options = {})
      line_item = grab_line_item_by_variant(variant, true, options)
      saved_quantity = line_item.quantity
      line_item = remove_from_line_item(variant, quantity, options)
      line_item.previous_changes[:quantity] = [saved_quantity,line_item.quantity]
      after_add_or_remove(line_item, options)
    end

    private

    # Override: Add tracking entry after a line_item is added or removed
    def after_add_or_remove(line_item, options = {})
      line_item = super
      Spree::Cart::Event::Tracker.new(
        actor: order, target: line_item, total: order.total, variant_id: line_item.variant_id
      ).track
      line_item
    end

  end
end

Spree::OrderContents.send(:prepend, Spree::OrderContentsWithTracker)
