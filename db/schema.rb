# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20171113094502) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "citext"

  create_table "catalogues", force: :cascade do |t|
    t.string   "url"
    t.citext   "lims_id",    null: false
    t.string   "pipeline"
    t.boolean  "current"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lims_id"], name: "index_catalogues_on_lims_id", using: :btree
  end

  create_table "permissions", force: :cascade do |t|
    t.citext   "permitted",       null: false
    t.string   "accessible_type", null: false
    t.integer  "accessible_id",   null: false
    t.datetime "created_at",      null: false
    t.datetime "updated_at",      null: false
    t.string   "permission_type", null: false
    t.index ["accessible_type", "accessible_id"], name: "index_permissions_on_accessible_type_and_accessible_id", using: :btree
    t.index ["permitted"], name: "index_permissions_on_permitted", using: :btree
  end

  create_table "products", force: :cascade do |t|
    t.string   "name"
    t.datetime "created_at",                             null: false
    t.datetime "updated_at",                             null: false
    t.integer  "catalogue_id"
    t.integer  "TAT"
    t.string   "requested_biomaterial_type"
    t.integer  "product_version"
    t.integer  "availability",               default: 1
    t.string   "description"
    t.string   "product_uuid"
    t.integer  "product_class"
    t.index ["catalogue_id"], name: "index_products_on_catalogue_id", using: :btree
  end

  create_table "work_orders", force: :cascade do |t|
    t.string   "status"
    t.datetime "created_at",                                                null: false
    t.datetime "updated_at",                                                null: false
    t.string   "original_set_uuid"
    t.string   "set_uuid"
    t.integer  "proposal_id"
    t.string   "comment"
    t.date     "desired_date"
    t.integer  "product_id"
    t.decimal  "total_cost",        precision: 8, scale: 2
    t.string   "finished_set_uuid"
    t.string   "work_order_uuid"
    t.string   "close_comment"
    t.citext   "owner_email"
    t.decimal  "cost_per_sample",   precision: 8, scale: 2
    t.boolean  "material_updated",                          default: false, null: false
    t.index ["owner_email"], name: "index_work_orders_on_owner_email", using: :btree
    t.index ["product_id"], name: "index_work_orders_on_product_id", using: :btree
  end

  add_foreign_key "products", "catalogues"
  add_foreign_key "work_orders", "products"
end
