# Odoo 19 Certification Exam -- All Modules

> Source-verified against Odoo 19 source code and official Odoo 19 documentation. Correct answer marked with **(True)**.
> Friend's exam questions + generated similar questions.

---

## General & User Interface (3 questions)

### 1. By default, when are followers notified about a record?

- By default, followers are notified for activities and discussions/messages
- By default, followers are notified for messages/discussions and @ mentions **(True)**
- By default, followers are notified for activities and log notes

> Source: `addons/mail/data/mail_message_subtype_data.xml` — `mt_comment` (Discussions) is the only subtype with `default=True`. `mt_activities` and `mt_note` both have `default="False"`.

### 2. How do you manually save or revert changes on a record (like a contact) when Odoo saves automatically?

- Clicking on File > Save in the browser menu or clicking on File > Revert changes in the browser menu
- There is no way to manually save data or revert changes in Odoo
- Click on the "Cloud" icon to the right of the breadcrumbs or use the ALT+S (or Control+S on macOS) shortcut. To revert a change, click the circle-arrow icon or use the ALT+J (or Control+J on macOS) shortcut. **(True)**

### 3. Inside a record, how do you schedule an activity for others or yourself?

- Click the 'Activities' tab at the top of the chatter and choose the activity type, due date, assignee, and add a summary **(True)**
- Click Schedule Activities in the Configuration Menu and add the activity type, and due date
- Click on the phone icon in the top menu bar and then click the '+' button to add an activity

---

## Users & Permissions (1 question)

### 1. Can a user with only 'Access Rights' set for their Administration permissions install new applications or modules?

- No, only Odoo can install applications and modules for customers
- No, a user with 'Administration: Access Rights' permissions cannot install an application(s) or a module(s) in Odoo, but they can send a request to activate the app/module to users that have the 'Administration: Settings' permissions **(True)**
- Yes, a user with 'Access Rights' permissions can install applications and modules in Odoo

---

## Inventory (22 questions)

### 1. Which of the following statements is TRUE about products with the product type set to 'Goods' and the Track Inventory field unchecked?

- Putaway rules cannot be configured for this product
- Reordering rules can be used to restock the product
- The product does not appear in packages **(True)**

### 2. Your warehouse is divided into zones for different product types. You want pickers to process several orders simultaneously while minimizing walking distance between zones. Which configuration best supports this goal?

- Enable Batch Transfers and group operations by the zone's stock location
- Use cluster picking so each picker handles the pick, pack, and ship steps separately
- Use Wave Transfers and assign a picker to retrieve items in each zone **(True)**

### 3. Which of the following statements about 'Inventory Adjustments' is FALSE?

- A stock move with 0 quantity is created from the storage location to the Inventory Loss location when the on-hand and counted quantities match
- You can set the frequency of inventory counts for product categories **(True -- this is the FALSE statement)**
- The barcode app shows all inventory counts to do at the selected location

### 4. When you update on-hand quantities from 5 units to 4 for a specific product, what stock moves are created?

- A move of 4 units from an 'Internal Location' to an 'Inventory Loss' location
- A move of 1 unit from an 'Internal Location' to an 'Inventory Loss' location **(True)**
- A move of 1 unit from an 'Inventory Loss' location to an 'Internal Location'

### 5. You're using the Average Cost valuation method, and the unit cost of a component suddenly increases. Where should you look to identify which stock moves caused the change?

- Review the component's receipts under Inventory > Operations > Receipts to check if one vendor price was unusually high
- Open Inventory > Reporting > Stock, locate the component, and click the Unit Cost to see all stock moves that affected its valuation
- Open Inventory > Reporting > Valuation and expand the grouped by view of products to view the component's stock valuation layers **(True)**

### 6. You receive two units of the same product on WH/IN/11 using the Average Cost valuation method. One costs $50, the other costs $22. Then, you open Inventory > Reporting > Stock and click the "Unit Cost" to view the valuation history. What do you see?

- One record for WH/IN/11 showing the average cost of $36
- Two separate records for WH/IN/11, one for each respective cost **(True)**
- One record for WH/IN/11 showing the total cost of $72

### 7. Which of the following best describes the difference between a reservation method and a removal strategy?

- A reservation method determines which orders receive available stock first, while a removal strategy determines which specific stock units are used to fulfill those orders **(True)**
- A reservation method decides how stock is reserved for orders while a removal strategy defines how products move between locations
- A reservation method requires the Lots & Serial Numbers setting to be enabled, while removal strategy requires the Storage Locations setting

### 8. Incoming products without defined putaway rules are being stored directly in WH/Stock, in a disorderly manner. You want products with undefined storage locations to go to WH/Stock/Misc. What should you do in Odoo to achieve this?

- Create a putaway rule with no product, product category, or package type and set the Store to location to WH/Stock/Misc **(True)**
- Create a custom route to WH/Stock/Misc
- Set the default location of Incoming Shipments to WH/Stock/Misc

### 9. You're configuring a packaging called "Pack of 6" to sell six soda bottles together. Soda's base unit of measure is units. You set the Package Type to Carton (representing the cardboard six-pack holder). On a delivery order for 6 units of soda and click "Put in Pack", what effect does this configuration have?

- Create a new package with the Package Type "Carton", with all 6 sodas inside **(True)**
- Create a new package with the Package Type "Carton", with all 6 sodas inside, but the unit is converted to 1 "Pack of 6" on the delivery order
- Creates one package containing all 6 sodas, but no Package Type is set, because it's not a thing

### 10. What does the 'i' button on the Replenishment dashboard NOT do?

- Display the forecasted arrival date of the product
- Triggers the reordering rule **(True)**
- Display lead times

### 11. You want to configure expiration information on a product. Which setup is required on the product form?

- The product must be of type 'Goods' and tracked by lots or serial numbers **(True)**
- The product can be any type, as long as Routes are enabled
- The product must be a consumable with packaging configured

### 12. What happens if you try to validate a receipt for a tracked product before assigning the required lot or serial number?

- Odoo validates the receipt and creates a temporary lot automatically
- Odoo shows an Invalid Operation popup, and the receipt cannot be validated until the lot or serial number is assigned **(True)**
- Odoo moves the product to Inventory Loss until a lot number is added later

### 13. Which settings must be enabled to configure the Closest Location removal strategy on a location?

- Packages and Lots & Serial Numbers
- Storage Locations **(True)** (location menu requires `group_stock_multi_locations`; `removal_strategy_id` field has no extra group — Multi-Step Routes is NOT needed)
- Replenishment and Product Packagings

### 14. Which statement about the Least Packages removal strategy is TRUE?

- It can be used without packages if products are stored in lots
- The Packages feature must be enabled to use it **(True)**
- It is only available when products are tracked by serial numbers

### 15. Which operation type does NOT offer reservation methods in Odoo?

- Delivery Orders
- Internal Transfers
- Receipts **(True)**

### 16. Your delivery operation type uses the 'Before scheduled date' reservation method, and there is enough stock on hand. Before the reservation date arrives, what can a user click to reserve the products early?

- Reserve Lot
- Check Availability **(True)**
- Validate

### 17. Which statement about the Package Use field is TRUE?

- It is visible by default on every package and defaults to Reusable Box
- It is only visible when Batch, Wave & Cluster Transfers and Packages are enabled, and it defaults to Disposable Box **(True)**
- It only appears for packages linked to a delivery carrier

### 18. A consultant wants to isolate transfers and manufacturing orders whose products or components are expected late. Which filter exists in Odoo 19 for that purpose?

- Backorder
- Late Availability **(True)**
- Reserved Only

### 19. Which company setting lets reordering rules trigger earlier than a just-in-time approach so buyers can get a head start on replenishment?

- Annual Inventory Month
- Replenishment Horizon **(True)**
- Reservation Method

### 20. Which of the following is NOT a 'Routes' option on a product form (under the Inventory tab)?

- Buy
- Upsell **(True)**
- Dropship

### 21. Which of the following is NOT a 'Variants Creation Mode' option while creating product attributes?

- Instantly
- Automatically **(True)**
- Dynamically

### 22. Using the 'Average Cost' (AVCO) costing method, will the unit cost of a product change when you deliver products?

- Yes
- No **(True)**

### 23. What type of document is the source of a receipt of products to your inventory?

- A Sales Order.
- A Manufacturing Order.
- A Quotation.
- A Purchase Order. **(True)**

### 24. When receiving products in Odoo, why is it important to correctly set the 'Destination Location' on the receipt?

- To track which vendor sent the shipment
- To ensure products are stored in the correct warehouse location **(True)**
- To calculate the total cost of goods received
- To automatically validate the receipt without further action

### 25. What do inventory transfers determine in Odoo's warehouse operations?

- The number of employees needed in the warehouse
- How products move within the warehouse and how shipments are processed **(True)**
- The pricing of products based on warehouse location
- Which suppliers can send shipments to the warehouse

### 26. Which Location Types are included in Odoo's inventory valuation calculations?

- Vendor and Customer
- Internal and Vendor
- Internal and Transit **(True)**
- Production and Inventory Loss

### 27. What is a "landed cost"?

- The price of an imported product
- The price to transport a product using ground shipping
- Expenses that must be paid, in addition to the cost of a product when purchasing it **(True)**
- The cost of moving a product from a ship onto land

### 28. Which costing method should I use to set the cost of a product as the average cost of every unit on-hand?

- Average Cost (AVCO) **(True)**
- Standard Price
- First In First Out (FIFO)
- This is not possible in Odoo

### 29. A product's reordering rule is set for a minimum of 20 units, and a maximum of 50 units. If a sales order is confirmed, and the forecasted quantity of the product is 15, how many units will be on the automatically generated RFQ?

- 5
- 20
- 35 **(True)**
- 50

### 30. What do you need to properly set up an automatic reordering rule?

- Set a rule for a product on the Reordering Rule dashboard.
- When the forecasted quantity falls below the defined minimum, an automatic reordering rule is triggered.
- Set a reordering rule and a default vendor for the product. **(True)**
- Nothing, Odoo will automatically purchase the items.

### 31. What is the purpose of a putaway rule in Odoo?

- To track employee attendance
- To automatically assign incoming products to specific storage locations **(True)**
- To manage customer invoices
- To generate sales reports

### 32. Which Inventory app setting needs to be enabled to use the 'Cross-Dock' route?

- 'Multi-Step Routes' **(True)**
- 'Cross-Docking'
- 'Push/Pull Routes'
- The 'Cross-Dock' route is available, by default

### 33. What do removal strategies determine?

- Which order gets the available stock first
- Which items should be picked or removed from stock, and when **(True)**
- Where items should be stored when removing them from stock
- How to use the most packages to fulfill an order

### 34. What removal strategy is best for goods that are considered perishable?

- First In First Out (FIFO)
- Least Packages
- Closest Location
- First Expired First Out (FEFO) **(True)**

### 35. How is the FIFO removal strategy assigned to a location in the Inventory app?

- By going to Warehouse > Location > Force Removal Strategy
- By going to Configuration > Location > Removal Strategy **(True)**
- By going to Warehouse > Shelf F > Removal Strategy
- By going to Configuration > Product Category > Removal Strategy

### 36. Which Inventory setting(s) are required to use the FEFO removal strategy?

- Lots and Serial Numbers, only
- Lots and Serial Numbers, Product Categories
- Storage Locations, only
- Expiration Date, Lots and Serial Numbers **(True)**

### 37. What is a traceability report used for?

- Viewing the movement of lots and serials **(True)**
- Calculating taxes
- Tracking sales only
- Setting up inventory categories

### 38. What product type must an item be to enable lot or serial tracking?

- Virtual
- Consumable
- Service
- Goods **(True)**

### 39. When can you set an expiry date for new lots of products entering the inventory?

- Directly at the reception of the products, when organizing lots on the Detailed Operations window, but *only* if the Expiration Dates feature is activated.
- Once lots are in-stock, you can add an expiry date in the Date tab of each lot form.
- A & B. **(True)**
- Odoo does *not* allow expiration dates to be set on products.

### 40. What needs to be updated to ensure scrapped products show in the Profit & Loss Report?

- A scrap 'Inventory Loss' location must be set with a loss account specified, and the product category must use FIFO or AVCO costing method, and the category's inventory valuation must be set to Perpetual. **(True)**
- Nothing – just scrap the products
- The expiration date
- This is *NOT* a feature in Odoo

### 41. How many transfers are created after confirming a sales order for a product that uses the 'Cross-Dock' route?

- One
- Two **(True)**
- Three
- Four

### 42. What does it mean when the 'Validate' button on a delivery order appears in purple?

- All or part of the order is ready to ship **(True)**
- The order has been shipped
- The order is waiting for products to be available before it can be shipped
- The 'Validate' button never appears in purple

---

## MRP (21 questions)

### 1. How are the costs of by-products accounted for?

- Only by setting a by-product cost share on the BoM
- Only by setting a by-product cost share on the manufacturing order
- By either setting a by-product cost share on the BoM or the manufacturing order **(True)**

### 2. Once a manufacturing order is confirmed, can you produce more quantities than initially expected?

- Yes **(True)**
- No
- Only in the Shop Floor module

### 3. You want to trigger quality checks when products arrive from vendors. How should you configure this?

- Create a quality control point on the "Receipt" operation type **(True)**
- Create a control point on the "Vendor Reception" operation type
- Create a quality check for each specific vendor

### 4. Your MPS shows a forecasted demand of 110 units for a product with a BoM Batch Size of 40. What happens when you click "Order"?

- 3 MOs are created, with 40 units in two MOs, and 30 units in the third MO **(True)**
- 3 MOs are created, 40 units each
- 4 MOs with 30 each

### 5. How do you configure a manufacturing product for subcontracting?

- Enable the 'Subcontracted' checkbox on the product's form
- Enable the 'Subcontracting' option in the 'BoM Type' field on the product's BoM **(True)**
- Add the 'Subcontract' route on the sales order that includes the product

### 6. Your subcontractor may consume slightly more or fewer components than expected. How can Odoo accommodate this?

- By setting Flexible Consumption to "Allowed" on the BoM **(True)**
- By sending more products than necessary on the Resupply Subcontractor route, and if there are extras, they can send them back
- By setting Flexible Consumption to "Allowed with warning" on the BoM

### 7. In the Shop Floor interface, how can an operator move an operation to an alternative work center?

- Pause the operation, close the work order, and create a new one for the correct work center
- Click "..." icon, select "Modify Routing", "Move to work center", and choose the alternative work center **(True)**
- Click "...", click "Settings", and choose "Move to another work center"

### 8. In the MPS, what does an orange-colored cell indicate about replenishment?

- A replenishment order has already been generated, but more quantities need to be ordered to meet the Safety Stock Target **(True)**
- The forecasted demand is higher than the actual demand, so the quantity to replenish is uncertain
- Too many units have already been replenished

### 9. When performing a work order, you can consume:

- Only products from the BoM, in the quantities defined by the BoM
- Only products from the BoM, but you can add extra quantities
- Any product **(True)**

### 10. How do you activate work order dependencies on BoMs?

- Work order dependencies are activated by default
- Work order dependencies must be activated from Manufacturing settings
- Work order dependencies must be activated in the Manufacturing settings, as well as on the 'Miscellaneous' tab for each specific BoM **(True)**

### 11. Where do you find the cost of processing a specific work order?

- Manufacturing app -> Operations -> Manufacturing Orders -> select MO -> Overview -> Operations section **(True)**
- Manufacturing app -> Operations -> Manufacturing Orders -> select MO -> Work Orders tab
- Manufacturing app -> Operations -> Work Orders -> select work order

### 12. What is the effect of enabling the 'Replenish Scrapped Quantities' option when scrapping components from an MO in the Shop Floor module?

- A purchase order is created to buy replacement components from a supplier
- This option does not appear when scrapping components
- A "Pick Components" transfer is automatically created to replace the scrapped component(s) **(True)**

### 13. What must be enabled for Work Centers to appear in Manufacturing?

- Lots & Serial Numbers
- Work Orders **(True)**
- Master Production Schedule

### 14. What happens if you create an unbuild order for a product with zero or fewer units on hand?

- Odoo blocks the unbuild order completely
- Odoo shows a warning about insufficient quantity, but you can still confirm the unbuild order **(True)**
- Odoo automatically creates an inventory adjustment before unbuilding

### 15. Which routes become available on products when subcontracting is enabled?

- Buy and Manufacture
- Resupply Subcontractor on Order and Dropship Subcontractor on Order **(True)**
- MTO and Dropship

### 16. What happens when you create a backorder from a manufacturing order after producing only part of the quantity?

- The original MO is canceled and replaced by a single new MO
- The original MO is split into two orders: one for the produced quantity and one backorder for the remaining quantity **(True)**
- Odoo updates the MO quantity and does not create any additional order

### 17. When can multiple manufacturing orders be merged into a single MO?

- Any time they belong to the same warehouse
- Only when they manufacture the same product with the same BoM **(True)**
- Only when each MO contains exactly one unit

### 18. What is the difference between the subcontracting routes 'Resupply Subcontractor on Order' and 'Dropship Subcontractor on Order'?

- Resupply uses components from the company's warehouse, while Dropship purchases components from a vendor and ships them directly to the subcontractor **(True)**
- Resupply is only for services, while Dropship is only for goods
- Resupply sends finished goods to the subcontractor, while Dropship sends raw materials back to the company

### 19. After creating a manufacturing backorder for a partially produced MO, what is the status of the two resulting orders?

- Both remain open until the backorder is completed
- Order `-001` contains the manufactured items and is closed, while order `-002` remains open for the remaining quantity **(True)**
- Order `-001` is deleted, and only order `-002` remains

### 20. In Odoo 19, which record groups related manufacturing orders and their backorders together?

- `procurement.group`
- `mrp.production.group` **(True)**
- `stock.warehouse.orderpoint`

### 21. Which model stores cross-document stock references that can link manufacturing and stock documents together?

- `stock.reference` **(True)**
- `stock.valuation.layer`
- `mrp.workorder.group`

---

## POS (3 questions)

### 1. What is required when configuring a payment method?

- Selecting a point of sale
- Selecting a terminal
- Selecting a journal **(True)**

### 2. Which setting allows you to send the request to the printer automatically?

- Print Full Receipt
- Early Receipt Printing
- Automatic Receipt Printing **(True)**

### 3. What happens when settling the remaining balance of a sales order in the POS?

- The down payment is deducted, allowing to complete the order **(True)**
- The down payment is ignored and the customer pays the full amount again
- A new sales order must be created for the remaining amount

---

## HR (5 questions)

### 1. How would you set up a mechanism where the amount of time off an employee gets depends on their number of days worked?

- You create a new Time Off type that does not require any approvals
- You create a new Allocation and set the Allocation Type to "Accrual Allocation" **(True)**
- You create a new Time Off type that does not permit Extra Day Requests

### 2. What is required when creating a new Job Position?

- The name of the position, the salary range, and the email alias for applicants to apply
- Only the name of the position **(True)**
- The name of the position, the job location, and expected skills

### 3. In the Payroll application, what source creates Work Entries?

- Working Schedules, Contracts, and Projects
- Working Schedules, Employees, and Time Off
- Working Schedules, Attendance, and Planning **(True)**

### 4. What is preconfigured in the Fleet app?

- Vehicle Manufacturers **(True)**
- Vehicle Models
- Vehicle Categories

### 5. How can a user with the required rights change an Employee's presence in the database from Present to Absent?

- In the Attendances app dashboard, click on the employee attendance record, and select Absent
- In the Employees app dashboard, click Presence Icon > Absent **(True)**
- On the Employee record, click Actions > Presence Control > Set Absent

---

## Spreadsheet (3 questions)

### 1. Which of the following is an advantage of converting an inserted pivot table into a dynamic pivot table?

- The pivot table can automatically expand to include new dimensions, e.g., a new salesperson or a new quarter **(True)**
- The pivot table can be manually sorted by measure by double-clicking the relevant column header
- The Odoo model on which the pivot table is based can be changed without having to reinsert the pivot table

### 2. When a spreadsheet is converted into a dashboard, where is the original spreadsheet saved?

- The spreadsheet remains in the Documents app but is automatically set to read-only
- The spreadsheet is saved in a special Dashboard assets folder, in the Documents app **(True)**
- The spreadsheet is deleted from the Documents app and can only be accessed via the Dashboards app

### 3. In a multi-company database with Company A, Company B, and Company C, how can you ensure only users from Company A and Company B can access a new dashboard you create?

- In the dashboard configuration, set which companies' users can access the dashboard **(True)**
- You need to duplicate the dashboard and assign each copy to a single company
- This is not possible; any dashboard is visible to all companies present in the database

---

## Accounting (20 questions)

### 1. A customer invoice with two lines, each with the same account and same 10% tax, is validated. How many items will the generated journal entry have?

- 2 journal items
- 3 journal items
- 4 journal items **(True)**

### 2. Is it possible to still make corrections after the Lock Everything lock date?

- No changes can be made after the Lock Everything lock date
- A user with Administrator access can set a temporary exception for themselves and other users, and select the desired exception duration **(True)**
- All changes are possible as long as the Hard Lock is not set

### 3. What depreciation methods are available for an asset?

- Declining, Straight line then Declining, and Straight line
- Declining, Declining then Straight line, and Straight line **(True)**
- Declining, Declining then Straight line, Straight line, and Progressive

### 4. How are follow-up actions triggered?

- Based on the number of days overdue starting from the creation date of the invoice
- Based on the number of days overdue starting from the due date of the invoice **(True)**
- Based on the number of days overdue starting from the invoice date of the invoice

### 5. Where is the Catalog view available?

- On invoices
- On vendor bills **(True)**
- On invoices and vendor bills

### 6. What information can you define on a contact record?

- The default payment method, preferred invoice sending method, and the invoice follow-ups **(True)**
- The invoice follow-ups, the payment terms, and the costing method
- The default payment terms, default payment method, and outstanding account

### 7. Can accounts belong to multiple companies?

- Yes, but only if the companies are set as branch offices
- No, each account can only belong to one company
- Yes, by merging accounts from various companies or mapping multiple companies on an account, each with a code **(True)**

### 8. How can you automatically cancel all journal entries from before a specific date?

- Set the specific date in the Invoicing Switch Threshold field in the Accounting settings **(True)**
- Select all the journal entries from before the specific date in the list view and click Action > Cancel
- In developer mode, go to the Advanced Settings tab of each journal that you want to cancel journal entries in, enable the Cancel Posted Entries With Hash field, and set the specific date

### 9. How can you include a spelled out invoice total on an invoice report?

- In the Accounting settings, enable the "Total amount of invoice in letters" feature **(True)**
- On the invoice form view in Studio, select the Total field and change the widget to "Amount in letters"
- On the invoice report in Studio, select the Total field and change the widget to "Amount in letters"

### 10. What checks are automatically processed when reviewing a tax return before its submission?

- Bank reconciliation, aged payables and receivables, loans, fixed assets, draft entries, and overdue payables and receivables
- Taxes and countries matching, draft entries, bill attachments, bank matching, and company data **(True)**
- Review, submit, and pay

### 11. How can you replace a 15% sales tax with a 0% sales tax for customers using the Tax Exempt fiscal position?

- On the 0% tax record, set the Fiscal Position to Tax Exempt and add the 15% tax to the Replaces field **(True)**
- On the 15% tax record, set the Fiscal Position to Tax Exempt and add the 0% tax to the Replaces field
- In the Tax Mapping tab of the Tax Exempt fiscal position, set the 15% tax as the Tax on Product and the 0% tax as the Tax to Apply

### 12. How can you choose to round an invoice's taxes per invoice line instead of per tax?

- On the individual invoice, in the Accounting section of the Other Info tab, set the Tax Rounding field to Per Invoice Line **(True)**
- The tax rounding is automatically set based on country regulations and cannot be changed
- Go to Accounting > Configuration > Taxes, and set the Rounding Method to Round per Line

### 13. With cash basis taxes, when does Odoo treat the tax as due?

- When the invoice is posted
- When the payment is made and reconciled **(True)**
- When the invoice due date is reached

### 14. Which cash discount tax reduction option reduces the tax only if the customer pays early?

- Always (upon invoice)
- On early payment **(True)**
- Never

### 15. In Analytic Plans, what does setting Default Applicability to 'Mandatory' do?

- It automatically creates an analytic account on every journal entry
- The entry cannot be confirmed if no analytic account is selected **(True)**
- It makes the analytic plan visible only to accounting administrators

### 16. In Odoo, when can an analytic budget be deleted?

- At any stage, as long as no journal entries are linked
- Only in Draft and Cancelled stages **(True)**
- Only after it has been Revised

### 17. What is the only legal method in Odoo to cancel, refund, or modify a validated invoice?

- Reset the invoice to draft and edit it directly
- Issue a credit note or debit note **(True)**
- Create a reversing journal entry from the journal items menu

### 18. What does the 'Reverse and Create invoice' option do when issuing a customer credit note?

- It creates a draft credit note only, with no reconciliation
- It creates and posts the credit note, reconciles it with the original invoice, and opens a new draft invoice **(True)**
- It creates a debit note instead of a credit note

### 19. How does Odoo number a credit note created from invoice `INV/2025/0004`?

- `CN/2025/0004`
- `RINV/2025/0004` **(True)**
- `INV/2025/0004-R`

### 20. If two fiscal positions both match a transaction through automatic detection, what decides which one Odoo applies?

- The fiscal position that appears first in the sequence **(True)**
- The fiscal position created most recently
- The fiscal position linked to the product category

---

## Timesheets (12 questions)

### 1. What does it mean when a timesheet line is in italics?

- It means the line has been invoiced
- It means the line has been validated
- It means the line is related to a project or task for which the user has not yet submitted a timesheet during the displayed period **(True)**

### 2. Which statement is true?

- Time off entries can automatically generate timesheet entries **(True)**
- Time off and timesheets entries are never linked
- You have to add time off entries manually in timesheets

### 3. How can you display the rankings on the timesheet leaderboard?

- By billing rate and hours invoiced
- By total time and hours invoiced
- By billing rate and total time **(True)**

### 4. When using Timesheets' default settings, what will be the duration of the timesheet entry if you stop the timer after 4 minutes and 30 seconds?

- 4 minutes
- 5 minutes
- 15 minutes **(True)**

### 5. What Grid view feature helps identify missing hours in timesheets?

- By filtering by missing hours
- The color-code system **(True)**
- The "Spot missing hours" feature

### 6. How are hours billed at a fixed price computed?

- These are sold hours coming from a sales order that still need to be timesheeted before being invoiced
- These are timesheeted hours linked to a sales order, where the invoicing policy is set to 'prepaid' **(True)**
- These are the actual timesheeted hours that can't be invoiced from the sales order

### 7. When entering timesheets, how is the timesheet cost generated?

- By setting an hourly cost on the employee form **(True)**
- By setting a cost on the product form
- By setting a timesheet cost on the task form

### 8. Which statement is true about billable tasks?

- You can change the sales order item or remove the sales order item (in which case the timesheet is considered 'non-billable')
- A billable task can contain timesheets that are not billable
- The timesheets of a billable task can be linked to different sales order items
- All of the above **(True)**

### 9. Which statement is true about invoicing timesheets?

- You must invoice all timesheets without distinction
- You can invoice timesheets from a specific period **(True)**

### 10. Looking at a timesheet view, what does "Anita Oliver 26:00" indicate?

- Anita Oliver worked 26 hours overtime, according to her contract
- Anita Oliver is missing 26 hours in her timesheets, according to her contract
- Anita Oliver worked 26 hours that week, according to her timesheets **(True)**

### 11. Which statement is true about timesheet editing restrictions?

- Employees cannot record or edit timesheets that predate their most recent validated timesheets **(True)**
- Employees cannot record or edit new timesheets when timesheets from an earlier period have not yet been validated
- Employees cannot encode/edit timesheets outside their working hours

### 12. Employee billing time target is configured:

- In HR settings of the individual employee **(True)**
- For all employees in Timesheets settings
- In the Billing Rate Leaderboard

---

## Project (14 questions)

### 1. How are tags shared between tasks?

- Tags are shared between all tasks of a single project
- Tags are shared between all tasks of all projects **(True)**
- Tags are not shared between tasks

### 2. The burndown chart represents, at a specific point in time:

- The number of tasks in each stage **(True)**
- The number of negative customer ratings
- The number of canceled tasks

### 3. When is a milestone displayed in red?

- When one or more of its tasks is marked as canceled
- When the milestone's deadline is today
- When the milestone's deadline has passed and at least one of its tasks is not marked as done or canceled **(True)**

### 4. How can you schedule a task you had previously created?

- By selecting a time frame in Gantt view
- By defining the planned date of the task on its form view
- By selecting a time frame in Gantt view or by defining the planned date of the task on its form view **(True)**

### 5. What does the blue color represent in the bar at the top of a Kanban stage?

- Sub-tasks
- Unassigned tasks **(True)**
- Tasks blocked by other tasks

### 6. When creating a task from a project's Kanban view, adding "24h" to the task title will:

- Add the text "24h" to the task's title
- Allocate 24 hours to the task **(True)**
- Set the task deadline's to be in 24 hours

### 7. How many task priority levels are available?

- One
- Three
- Five
- Four **(True)** — Low (0), Medium (1), High (2), Urgent (3)

### 8. When creating a task from a project's Kanban view, adding "#priority" to the title will:

- Add a "priority" tag to the task **(True)**
- Set's the task's priority to high
- Add the text "#priority" to the task's title

### 9. Is it possible to define different Kanban stages for different projects?

- No
- Yes **(True)**

### 10. What kind of costs are taken into account in the project updates?

- The timesheet costs of your employees
- Any cost linked to the analytic account of the project
- Expense costs linked to the project's sales order
- All of the above **(True)**

### 11. Which of the following statements is true about sub-tasks?

- Tasks and sub-tasks cannot be in different projects
- Sub-tasks can have their own sub-tasks **(True)**

### 12. Which statement is true about the "My Tasks" pipeline?

- The tasks in the "My Tasks" pipeline are automatically dispatched across stages based on their deadline
- The tasks in the "My Tasks" pipeline are automatically dispatched across stages based on their next activity date
- The tasks in the "My Tasks" pipeline are manually dispatched across stages by the user **(True)**

### 13. What condition(s) must be met for the milestones of your project to be invoiced?

- A sales order item must be set on the milestone
- The milestone must be marked as reached
- All of the above **(True)**

### 14. How can you mark the milestones of your project as reached?

- Milestones have to be manually marked as reached **(True)**
- Milestones are automatically marked as reached when all of their tasks are done

---

## Knowledge (4 questions)

### 1. Which article does Knowledge open when you first open the app?

- The last article I edited
- The first article of my menu **(True)**
- The last article I read

### 2. Who can edit an article in the Workspace?

- Any contributor with 'Can read' access
- The author only
- Everyone, as long as it's in the default company access **(True)**

### 3. What happens to your private article if you set the 'General Access' to 'Can Read' or 'Can Edit'?

- It stays in the private category, and others can read or edit it
- It is automatically sent to the Shared category
- It is automatically sent to the Workspace category **(True)**

### 4. What can you do if you accidentally delete an article's section?

- Restore the previous version of the article **(True)**
- Restore the article from the 'Archived' articles
- Restore the article from the 'Trash'

---

## eCommerce (10 questions)

### 1. Are there specific ways to display product attributes over a product card on the /shop page?

- No, they are always visible
- Yes, you can choose to display them or not or to display them only on Hover **(True)**
- You can only choose to hide them or display them on scroll

### 2. Where can you add Optional Products?

- On the frontend of the product page with the Editor
- In Website > eCommerce > Products
- In the product backend, on the Sales tab **(True)**

### 3. Where can you automate Ribbons and Badges? How many 'assign' options do you have?

- On the back-end, in Product Ribbons. When a Ribbon is selected, you can choose an option between 'Manually', 'On Sale', 'When new' or 'When out of stock' **(True)**
- On the back-end of a specific product only, in the Sales tab, you can choose an option between 'Manually', 'On Sale', 'When new' or 'When out of stock'
- On the back-end of a specific product only, in the Attributes & Variants tab, you can choose an option between 'Manually', 'On Sale', 'When new'

### 4. What can you add to a product to highlight it in your catalog and/or on the product page?

- A ribbon
- A badge
- A ribbon or a badge **(True)**

### 5. Is it possible to set a custom internal reference for each product variant?

- Yes **(True)**
- No

### 6. What pricelist is used on your online shop for visitors who have not logged in?

- The default 'eCommerce' pricelist linked to your website **(True)**
- There is no pricelist for visitors
- The default 'Public Pricelist' pricelist

### 7. How can you display prices with the tax included on your eCommerce?

- Enable the 'Tax included' option in the settings **(True)**
- Create one pricelist 'Taxes included' and one 'Taxes excluded', and let the customer choose
- Enter the desired price in the 'Tax-included price' field in the product template

### 8. When does Odoo generate a quotation from the eCommerce module?

- When a product is added to the cart **(True)**
- When clicking 'Process Checkout' in the shopping cart
- When payment is validated

### 9. From which screen can you put a ribbon on a product in the eCommerce shop?

- From the menu Configuration > Sales
- From the 'Discount & Loyalty' program
- From the /shop page in edit mode, after you click on a product **(True)**
- From the front-end, on the catalog page, when a product image has been selected, or from the back end on the product form

### 10. What pricelist configuration option allows end users to choose a specific pricelist while shopping online?

- Selectable **(True)**
- Optional
- Customer Choice

---

## Website (8 questions)

### 1. Is it possible to hide a building block for a specific language?

- Yes, by using block conditional visibility **(True)**
- No, you can only customize text between languages
- No, it's not possible to hide a block by language but only by country

### 2. On what support can you decide to hide certain content blocks when editing your website?

- Desktop
- Desktop and mobile **(True)**
- Desktop, mobile, and tablet

### 3. What social media wall can be displayed on your website?

- Instagram **(True)**
- TikTok
- LinkedIn

### 4. How can you customize your website on mobile?

- You can edit the website completely compared to the desktop; it's like two different versions
- You can reorder elements, resize columns, and hide some blocks **(True)**
- You cannot edit the mobile version

### 5. After installing the Website app, you pick a theme. Can you switch to a different theme later?

- Yes, using the website editor, go to the 'Theme tab' and choose 'Switch Theme'
- No, this choice is definitive, and you'll have to create another website
- Yes, switch to 'debug' mode, then go to Website > Settings **(True)**

### 6. Can you save a snippet for later use?

- No, snippets cannot be saved for future use
- Yes, it is automatically saved in the templates section
- Yes, it is saved in the custom building block menu **(True)**

### 7. How can you get a submenu in the menu?

- Open Website > Site > Menu Editor, then drag a menu item to the right and underneath another menu to nest it as a submenu **(True)**
- Activate developer mode and then click on add submenu in the Menu Editor
- Go to the website editor, in the 'Theme' tab and select add submenu

### 8. What feature can you use to emphasize part of text (e.g. circle around, underline with dots, etc.)?

- Select the text and use Bold
- Select the text and use one of various highlight options **(True)**
- Select the text, use the brush and add background color and form

---

## Marketing (8 questions)

### 1. In Odoo, 'UTM' is used as an abbreviation for:

- Universal Text Message — the ability to automatically translate an SMS text message in the recipient's language
- Unit Training Management — the ability to include machine learning in your mailing
- Urchin Tracking Module — the ability to track the effectiveness of marketing campaigns **(True)**

### 2. Marketing campaigns are:

- Used to centralize (and report on) marketing efforts revolving around a central topic **(True)**
- Used to electronically spam random email addresses without any direction or specific intent
- A series of checklists marketers must complete before sending any communications

### 3. To track a link included in a mailing:

- You must use the OLG (Odoo Link Generator) application
- You don't need to do anything; Odoo does it for you **(True)**
- You must manually add a piece of code in each mailing

### 4. Assuming it's January 7th, 2024, which event are you able to register for?

- An event with a sale start date of January 1, 2024, with a maximum number of 50 registrants, and 50 have registered
- An event with a sale start date of January 9, 2024, with a maximum number of 50 registrants, and 0 have registered
- An event with a sale start date of January 4, 2024, with a maximum number of 75 registrants, and 18 have registered **(True)**

### 5. Which of the following is NOT a valid Marketing Automation activity trigger?

- 1 week after an email has bounced
- 2 days after an email has been forwarded **(True)**
- 0 hours after an email has been clicked

### 6. What condition is required to send 'Push Notifications'?

- Submit email
- Enable push
- Allowed **(True)**

### 7. Which of the following social media networks is NOT present in Odoo 19?

- X (formerly Twitter)
- Facebook
- TikTok **(True)**

### 8. In SMS Marketing, under the 'A/B Tests' tab on a message form, which of the following is NOT a 'Winner Selection' option?

- Highest Click Rate
- Revenues
- Opportunities **(True)**

---

## CRM (18 questions)

### 1. What happens to an opportunity that is marked as 'Lost'?

- The opportunity is archived and hidden from the main dashboard but can be accessed using Filters > Lost **(True)**
- The opportunity is moved to the Lost stage in the Kanban view and remains visible but inactive
- The opportunity is archived and removed from all dashboards but can still be accessed through advanced search options

### 2. You need to add a new contact to a company, but the contact has a different address from the company. What should you do?

- On the company's contact record, under the Contacts & Addresses tab, add a new contact and select the Other Address type **(True)**
- On the company's contact record, under the Contacts & Addresses tab, add a new contact and select the Invoice Address type
- Create a separate contact record with the new address and link it to the company using the Parent Company field

### 3. How many quotations or sales orders can you create from a single opportunity?

- Unlimited quotations, but only one sales order
- As many quotations and sales orders as you want **(True)**
- Only one quotation or sales order can be active at a time

### 4. What does the Probability field on an opportunity represent?

- The likelihood that the opportunity will move to the next stage in the pipeline
- The likelihood of receiving a response to a quotation or offer
- The likelihood of successfully closing the deal with the prospect **(True)**

### 5. How can you manually link an existing sales order to an existing opportunity in Odoo?

- Through the Link Documents button on the opportunity
- Under the Other Info tab on the sales order **(True)**
- By creating a new opportunity and merging it with the sales order

### 6. Which of the following is true about Recurring Revenues in Odoo?

- They are available only if the Subscriptions app is installed
- They can be activated on each individual opportunity
- They can be activated in CRM Settings **(True)**

### 7. Which of the following is not a Lead Enrichment option on the CRM Settings page?

- Enrich leads on demand only
- Enrich leads based on customer behavior **(True)**
- Enrich all leads automatically

### 8. How can you access an individual sales team's pipeline in Odoo?

- Go to Sales > Teams > Pipeline **(True)**
- Go to Configuration > Teams > Pipeline
- Go to Sales > Opportunities and filter by team

### 9. How can you forward leads to resellers in Odoo?

- Install the Resellers module
- Enable the Resellers setting in Configuration **(True)**
- Assign leads manually to reseller contacts without activating any settings

### 10. What visual indicator shows that an opportunity has "rotted" in Odoo?

- A red warning icon appears next to the opportunity name in the list view
- The opportunity's Kanban card is highlighted in red **(True)**
- The stage header flashes to indicate a rotted opportunity

### 11. What happens when you click one of the colored bars at the top of a CRM pipeline kanban stage?

- Nothing happens
- Odoo only displays opportunities in that stage that share the same color-code, which represents its current Activity Status
- It only displays opportunities with a specific activity status (Planned, Today, Overdue) for all stages **(True)**

### 12. What is the impact of setting a sales team on a pipeline stage?

- Only users from this sales team are able to drop opportunities in this stage
- Only users from this sales team are able to see this stage **(True)**
- Opportunities dropped in this stage are automatically assigned to the sales team

### 13. Which of the following operations can you achieve by sending an email to an Odoo email alias?

- Create a lead **(True)**
- Convert a lead to an opportunity
- Change the stage of a lead

### 14. On average, a lead is more likely to be won over an opportunity.

- True
- False **(True)**

### 15. Which field does Odoo use to detect duplicate leads?

- Contact name (email) **(True)**
- Opportunity name

### 16. What does the 'Closed Date' on an opportunity indicate?

- The date the opportunity was created
- The date the opportunity was won or lost **(True)**
- The date the opportunity was deleted

### 17. When looking at a company's contact record, the Opportunities smart button will show:

- All of the opportunities related to the company and the company's contacts related to those opportunities **(True)**
- Only the opportunities that were won
- Only the opportunities that have activities scheduled

### 18. How can you customize the criteria used for Predictive Lead Scoring?

- Navigate to Configuration > Settings, click 'Update Probabilities' beneath the 'Predictive Lead Scoring' setting, and proceed to customize criteria **(True)**
- Navigate to Configuration > Sales Teams, click 'Update Probabilities' beneath the 'Predictive Lead Scoring' setting, and proceed to customize criteria
- (In Developer Mode) Click Reporting > 'Update Probabilities', and proceed to customize criteria

---

## Survey (4 questions)

### 1. What is a 'Matrix' question?

- Answers require participants to input HTML code
- Rows of questions that participants answer by selecting an option from a column **(True)**
- A question attendees can try multiple times (without penalty)

### 2. In the 'Options' tab of a survey form, what are the 'Display Progress as' options?

- 'Percentage left' and 'Progress bar'
- 'Percentage left' and 'Number'
- 'Progress bar' and 'Number' **(True)**

### 3. What does the Allow Roaming option let participants do during a survey?

- Pause the survey and complete it at a different day or time
- Share their responses with other participants
- Go back to previous pages of the survey if needed **(True)**

### 4. Which of the following options is not available in a Live Session?

- Survey time limit **(True)**
- Scoring without Answers
- Matrix Questions

---

## Sales (22 questions)

### 1. Assuming you have enough stock to fulfill an order, what will the scheduled delivery date be when a sales order is confirmed on September 1st -- for a product that has a customer lead time of 5 days, and a security lead time of 2 days?

- September 8th
- September 6th **(True)**
- September 4th

### 2. What does it mean when a product has the "Buy" box checked in the Inventory tab on its product form?

- When a reordering rule set on the product is triggered, a Request for Quotation to purchase the product from a vendor will be generated **(True)**
- When a reordering rule set on the product is triggered, a manufacturing order will be generated
- When a sales order is confirmed, a manufacturing order will be generated

### 3. Can any product be used in a sales order?

- Yes, you can use all your products
- No, you can only use products you currently have in stock
- No, you can only use products that you've marked under 'Sales' on the product form **(True)**

### 4. How could you prevent a specific product from being used in quotations?

- By archiving the product
- By setting a blocking warning on the product ('Sale Warnings' setting must be activated)
- Both solutions are correct **(True)**

### 5. How would you configure Odoo to offer free shipping when buying any 2 cabinets?

- Create a pricelist focused on a minimum quantity of '2' for the product 'cabinet'
- Create a promotion program. Configure conditional rule with a Minimum Quantity of '2,' and add all 'Cabinet' products in the 'Products' field. Then, configure a Reward with the Reward Type of 'Free Shipping' **(True)**
- This is not possible in Odoo

### 6. How would you configure Odoo so that the product 'Office Chair' appears as a suggested option when a customer adds the product 'Conference Chair' to their cart in the online store?

- List the Office Chair as an 'Optional Product' on the Conference Chair's product form (under 'Sales' tab) **(True)**
- List the Office Chair as an 'Alternative Product' on the Conference Chair's product form (under 'Inventory' tab)
- List the Conference Chair as an 'Alternative Product' on the Office Chair's product form (under 'General Information' tab)

### 7. When a customer finalizes a purchase in the online store:

- Odoo automatically creates a sales order and invoice in the Sales app (if the 'Automatic Invoice' setting is activated) **(True)**
- Odoo automatically creates a quotation in the Sales app (if the 'Automatic Quotation' setting is activated)
- Odoo automatically creates a new opportunity in the CRM pipeline (if the 'Automatic Opportunity' setting is activated)

### 8. How would you configure a promotion to offer the following: 'Receive a free tote bag with your purchase of $50 or more'?

- Create a Conditional Rule with the minimum quantity set to '50' and create a Reward with Reward Type set to 'Discount.' Then, enter 'Free Tote Bag' in the Description On Order field
- Create a Conditional Rule with the minimum purchase set to '50' and create a Reward with a Reward Type set to 'Free Shipping.' Then enter 'Free Tote Bag' in the Description On Order field
- Create a Conditional Rule with the minimum purchase set to '50' and create a Reward with Reward Type set to 'Free Product.' Then, create or select 'Tote Bag' in the Product field **(True)**

### 9. How can you send a preliminary invoice to a customer *before* a sale is confirmed?

- Enable the 'Pro-Forma Invoice' setting, create a quotation, and click the 'Send PRO-FORMA Invoice' button **(True)**
- Enable the 'Pro-Forma Invoice' setting, go to the Sales App, click the "To Invoice" header, and select "Send Invoice (Pro-Forma)"
- You can just send a quotation, since a quotation is technically a kind of invoice

### 10. What is a valid configuration for an achievement-based commission plan?

- 10% of all sales to a specific customer each quarter
- $1,000 for reaching $25,000 in sales each month **(True)**
- 5% of the margin of all sales across a specific product category over the course of a year

### 11. A product uses the 'Delivered quantities' invoicing policy. When does Odoo allow you to create the invoice?

- As soon as the quotation is sent
- Only after at least a partial delivery has been validated **(True)**
- Only after the full ordered quantity has been delivered

### 12. If the global invoicing policy is set to 'Invoice what is delivered', what happens to the Automatic Invoice feature?

- It remains available for online payments
- It cannot be activated **(True)**
- It becomes mandatory for eCommerce orders

### 13. What is TRUE about requesting a 100% down payment on a sales order?

- It is identical to full payment of the sales order, so no further invoice can be created
- It is not the same as full payment, and the sales order still keeps the Create Invoice button for a final invoice **(True)**
- Odoo automatically converts the sales order into a paid invoice without posting a down payment invoice

### 14. If both Online Signature and Online Payment are enabled on a quotation template, what must the customer do to confirm the order?

- Provide either a signature or a payment
- Provide both a signature and a payment **(True)**
- Only sign the quotation; payment is always optional

### 15. Where do accessory products appear in the online customer's journey?

- At the bottom of the product page
- In the cart review / checkout step as suggested accessories **(True)**
- Only inside the PDF quotation

### 16. What happens if you try to create a customer invoice for a product using the 'Delivered quantities' invoicing policy before any quantity has been delivered?

- Odoo creates a zero-value invoice
- Odoo raises an error indicating there is no invoiceable line **(True)**
- Odoo automatically switches the product to 'Ordered quantities'

### 17. If the Sales app is configured to invoice what is delivered and the Inventory app is not installed, how can delivered quantity be provided?

- It cannot be done without Inventory
- The delivered quantity must be manually entered on the sales order **(True)**
- Odoo automatically assumes the ordered quantity was delivered

### 18. In Odoo 19, which field on the sales order line allows a consultant to combine routes such as MTO and Buy directly on the line?

- `route_id`
- `route_ids` **(True)**
- `procurement_group_id`

### 19. Why can a quotation section that already hides prices not be marked as optional?

- Optional sections cannot contain hidden prices or hidden composition **(True)**
- Optional sections are only available on quotation templates
- Optional sections are limited to internal users

### 20. A customer is interested in an expensive product. The supplier delivery lead time is less than your customer delivery lead time, and you rarely sell this product. What is the best procurement method?

- Use the Master Production Schedule tool
- Configure this product as a 'Consumable' type
- Set this product route to 'Replenish on Order (MTO)' **(True)**

### 21. If you would like to group specific sales order lines together to generate subtotals, what feature would you use on the quotation/sales order?

- Product categories
- Sequences
- Sections **(True)**

### 22. Which of the following is true when you activate the 'Margins' setting in Sales > Configuration > Settings?

- Changing the cost price on a sales order line will recompute a new unit price, according to the calculation on the pricelist
- Sales order lines can show both the unit price and cost price of the product, as well as the margin, by calculating the difference between the unit price and the cost price **(True)**
- Margins will only display on confirmed sales orders, not on quotations

---

## AI (5 questions)

### 1. Which of the following can be used as Sources for an AI Agent?

- Only text fields and record notes
- Uploaded files, Knowledge articles, docs from the Documents app, and website links **(True)**
- Knowledge articles and docs from the Documents app only

### 2. What does it mean when an AI Agent is not assigned any Topics?

- The agent can provide information, but cannot make changes to the database or perform tasks
- The agent can only perform tasks based on the information provided in its Sources
- Leaving the Topics field empty means the agent has access to all topics and tools in the database **(True)**

### 3. How can you enable AI to transcribe meetings in Odoo?

- In the Discuss app, go to Configuration > Voice & Video Settings and enable AI Transcription
- In Knowledge > Browse Templates, select Meeting Minutes
- Type "/" to open the command palette on an article, note tab, or description tab, and select Voice Transcript **(True)**

### 4. If an AI Agent with "Restrict to Sources" enabled is asked something outside its defined Topics or Sources, how does it respond?

- It informs the user it doesn't have the information or permissions to respond **(True)**
- It automatically switches to another provider
- It guesses the most likely answer based on previous responses

### 5. How many AI Agents can you have in a single Odoo database?

- One per installed app
- A maximum of five active agents per user
- As many as needed, there's no fixed limit **(True)**

---

## Studio (6 questions)

### 1. In the Form view, what is the key difference between a Primary button and a Secondary button?

- The design of the buttons (e.g., color and prominence) guide the user's main action **(True)**
- Primary buttons execute server actions, while secondary buttons call Python methods
- Secondary buttons are hidden on mobile views, while primary buttons are visible

### 2. To display a star rating system for a field with four values (e.g., 0 to 3 stars), which field type and widget could you use?

- Selection field with the Badge widget
- Priority field with the Radio widget
- Selection field with the Priority widget **(True)**

### 3. Which property should you use on a field if you want to display an example of how the field should be completed (e.g., 'Enter up to 50 characters')?

- Placeholder **(True)**
- Help Tooltip
- Default Value

### 4. How can you ensure users can only choose a year and a month in a date selector, rather than a day?

- Set the Date format to Numeric and disable 'Show Day'
- Set the 'Minimal Precision' field to 'Month' and the 'Maximal Precision' field to 'Year' **(True)**
- Enable 'Show Year' and 'Show Month'

### 5. What does the 'Existing Fields' section consist of when customizing a view in Studio?

- All fields in the model that were not added to the current view **(True)**
- All fields available on the model, including those already visible in the current view
- All fields in the model that were explicitly made invisible in the current view

### 6. If an action only needs approval in certain circumstances, how can you configure this?

- Add the details in the 'Description' field; the approver will see a message indicating whether or not approval is needed
- When setting up an approval step, click the filter icon and define the relevant conditions **(True)**
- After the basic approval rule is set up, create an automation rule to further define the circumstances in which it applies

---

## Purchase (20 questions)

### 1. You configure a product to calculate its cost on a 'Standard Price' basis, and you currently have 8 units of it in stock, with a cost of $100/unit. If you were to purchase and receive 2 more units at a price of $10/unit, what will your new cost be?

- 100 **(True)**
- 90
- 82

### 2. What does setting a product's 'Control Policy' to 'On ordered quantities' do?

- When creating a vendor bill, a product's price comes from the purchase order, and the quantity to invoice comes from the receipt
- When a purchase order is confirmed, a vendor bill is automatically generated
- When uploading a vendor bill, the quantity and price are automatically set to the ordered amount **(True)**

### 3. Given that you currently have 10 units on hand and 5 forecasted units of the product, the min = 10, max = 40, when the reordering rule is triggered, how many additional units will be ordered?

- 10
- 30
- 35 **(True)**

### 4. If you have several lines for the same vendor in a product purchase price list, which one will be selected?

- The first in the list
- The cheapest if the condition of quantity is met
- The one with the biggest quantity under the quantity ordered **(True)**

### 5. Your warehouse tracks liquid inventory in liters, but your vendor sells in gallons. You create Gallon as a new Unit of Measure. What condition must be met for Odoo to automatically convert between gallons and liters when you purchase the product?

- Create the "Gallons" unit, set its Reference unit to liters, and if an RFQ uses gallons as the unit, the receipt will say liters
- Create the gallons unit to be in the "Volume" UoM category that uses liters as the reference unit of measure **(True)**
- Odoo converts automatically without any setup, thanks to AI

### 6. When a preset Discount is set on a Vendor Pricelist for a specific product, can the discount be overridden on an RFQ?

- No, the Discount must be changed in the 'Discount (%)' field on the Vendor Pricelist itself
- No, once the Discount is set it won't reset until the Vendor changes their pricing
- Yes, the Discount can be modified directly on the purchase order line when creating an RFQ **(True)**

### 7. You set "Based On" to Last 7 days and "Replenish for" to 15 days. Odoo suggests quantities for several products. What data is Odoo using to generate these suggestions?

- It only considers confirmed purchase orders in the last 7 days to compute daily demand, then multiplies by 15
- It averages the price of the product over the last 7 days to compare to what you're paying for the next 15 days to make sure your vendors aren't ripping you off
- It looks at quantities delivered over the past 7 days to compute daily demand, then multiplies by 15 and subtracts on-hand stock **(True)**

### 8. You have a product with a reordering rule set to a minimum of 5 units and a maximum of 10 units. The rule is set to be triggered manually. How can you manually trigger this reordering rule?

- When the on-hand quantity falls below 5 units
- By waiting for the scheduler to run
- By clicking the 'Order' button in the Replenishment report **(True)**

### 9. What is the default bill control policy for a service product in Purchase?

- On received quantities
- On ordered quantities **(True)**
- It depends only on the vendor pricelist

### 10. The 3-way matching feature is intended to be used with which bill control policy?

- On ordered quantities
- On received quantities **(True)**
- Either policy works identically

### 11. What happens after a blanket order is confirmed?

- Odoo creates and confirms a purchase order automatically
- A new vendor line is added under the Purchase tab of the products included in the agreement **(True)**
- The agreement becomes read-only and can no longer be used for replenishment

### 12. In a call for tenders workflow, where do you create alternative RFQs from the original RFQ?

- From the product's Purchase tab
- From the Alternatives tab on the original RFQ **(True)**
- From Accounting > Vendors > Bills

### 13. What is the default bill control policy for a goods-type product in Purchase?

- On delivered quantities **(True)**
- On ordered quantities
- It is always blank until manually selected

### 14. What happens if a product uses the 'On received quantities' bill control policy and you try to create a vendor bill before receiving anything?

- Odoo creates the bill using the ordered quantity
- Odoo shows an error because nothing has been received yet **(True)**
- Odoo automatically changes the product to 'On ordered quantities'

### 15. After confirming a blanket order, what can still be changed on the agreement?

- Nothing; confirmed blanket orders are fully locked
- Products, quantities, and prices can still be edited, added, or removed **(True)**
- Only the expiration date can be changed

### 16. A vendor wants RFQs grouped according to expected arrival date or even by weekday. Where is this configured in Odoo 19?

- In Purchase settings under RFQ grouping
- On the vendor form with the `Group RFQ` and `Week Day` fields **(True)**
- On each individual RFQ template

### 17. When using the Upload Bill widget from purchase orders, which selection is blocked by Odoo 19?

- Selecting purchase orders from different vendors **(True)**
- Selecting several purchase orders from the same vendor
- Selecting a purchase order that already has a receipt

### 18. What will the scheduled purchase order date be if you validate a sales order on October 25th with a MTO route, with a 'Customer Lead Time' set to 10 Days and 'Vendor Lead Time' set to 6 Days?

- October 29th **(True)**
- October 19th
- October 25th

### 19. Is a receipt automatically created when an RFQ is confirmed?

- Yes, if the Inventory app is installed
- Yes, if there are some stockable/consumable products in the quotation
- Only if the 2 other answers are true **(True)**

### 20. A product has a purchase lead time of 15 days and there is a purchase security lead time of 5 days. What will be the scheduled date for the receipt of a purchase order confirmed today?

- This will be known at reception only
- Today +20 days
- Today +15 days **(True)**

---

## Documents (3 questions)

### 1. By default, how long do items moved to the trash remain there before being permanently deleted?

- 7 days
- 30 days **(True)**
- 90 days

### 2. You want to grant access to a Documents folder to an external contact. What must be enabled first?

- Access through link **(True)**
- Discoverable access
- Editor access for internal users

### 3. Which statement about File centralization for Accounting documents is TRUE?

- It cannot be disabled, and Odoo automatically creates a sub-folder per journal type while adding the journal name as a tag **(True)**
- It is optional and only available for Purchase journals
- You must manually create a folder for every journal before synchronization starts

---

## Sign (3 questions)

### 1. When can a signature request be sent via a shareable link from the Sign app?

- Only when the document or document envelope has a single signer **(True)**
- Only when the template is linked to an Odoo model
- Only after the requester signs first

### 2. When you send a signature request from an Odoo record, who is automatically added as a signer?

- The current internal user who opened the record
- The related customer (or the relevant party) **(True)**
- All followers of the record

### 3. What does the "Add certificate on each page" option do?

- It adds the full certificate of completion as a final extra page
- It adds a reference of the certificate of completion to each page of the document **(True)**
- It only sends the certificate by email after signing is complete

---

## Planning (3 questions)

### 1. In the Planning schedule, what do diagonal stripes on a shift mean?

- The shift is planned but not yet published **(True)**
- The shift is published and currently in progress
- The shift conflicts with approved time off

### 2. Which employee cannot be assigned by the Auto Plan feature solely because of role configuration?

- An employee with no Planning roles **(True)**
- An employee with more than one Planning role
- An employee whose default role differs from the shift role

### 3. What is the effect of assigning a default Planning role to an employee?

- It is automatically selected on shifts and given priority over the employee's other roles during auto-assignment **(True)**
- It only changes the color of the employee's shifts in the schedule
- It is used only for reporting and does not affect planning behavior

---

## Appointments (3 questions)

### 1. What does the "Select Time then auto-assign" assignment method do?

- Customers choose a user/resource first, then select a time slot
- Customers select a time slot and Odoo automatically assigns the user/resource **(True)**
- Customers select a time slot, but an internal user must manually assign the resource afterward

### 2. In a resource-based appointment with managed capacities, what maximum capacity does the website display by default before a system parameter is added?

- 10
- 12 **(True)**
- Unlimited

### 3. A 1-hour appointment type has a Pre-Booking Time of 1 hour. At 2:00 PM, a customer tries to book 2:45 PM for the same day. What is the first available time?

- 2:45 PM
- 3:00 PM
- 4:00 PM **(True)**

---

## Helpdesk (3 questions)

### 1. Which feature is enabled by default on newly created Helpdesk teams?

- Refunds
- SLA Policies **(True)**
- Field Service

### 2. When does the Return button appear on a Helpdesk ticket?

- Only when the ticket is linked to a confirmed sales order
- Only when the customer has a recorded delivery in the database **(True)**
- Only when the team has both Refunds and Repairs enabled

### 3. When creating a Field Service task from a Helpdesk ticket, when does the Worksheet Template field NOT appear?

- When the Helpdesk ticket has no assigned salesperson
- When the Field Service project assigned to the team does not have worksheets enabled **(True)**
- When the customer has not signed the ticket yet

---

## Sales -- Additional (10 questions)

### 20. When you cancel a confirmed sales order, what happens to invoices that have already been posted (validated)?

- All linked invoices are automatically canceled along with the sales order
- Only draft invoices are canceled; posted invoices remain untouched **(True)**
- Odoo prevents the cancellation entirely until all invoices are manually reversed

### 21. The 'Lock Confirmed Sales' setting is enabled. A salesperson needs to add a product line to a confirmed sales order. What must happen first?

- The order must be canceled and recreated
- The order must be unlocked before any edits can be made **(True)**
- The salesperson can edit freely because the lock only prevents deletion

### 22. A product's cost (standard_price) changes after a sales order is confirmed. What happens to the margin displayed on that SO line?

- The margin stays fixed at the cost recorded when the SO was confirmed
- The margin is automatically recalculated based on the purchase_price field, which was set when the line was created **(True)**
- Odoo shows a warning but does not recalculate until the user clicks 'Recompute Margins'

### 23. You create a 50% down payment invoice, then deliver all products, and then create the final invoice with 'Deduct down payments' checked. What appears on the final invoice?

- Only the remaining 50% balance as a single invoice line
- The full product lines plus a negative line deducting the down payment amount **(True)**
- A separate credit note for the down payment and a full invoice for the total

### 24. A fiscal position has 'Detect Automatically' enabled with a country, a country group, and a ZIP range configured. In what order does Odoo evaluate these conditions?

- Country first, then ZIP, then country group
- VAT required first, then ZIP range, then country/country group **(True)**
- Country group first, then country, then ZIP range

### 25. Which of the following is NOT a valid loyalty program type in Odoo 19?

- Next Order Coupons
- Buy X Get Y
- Tiered Discount **(True)**

### 26. A sales order has a partner-level warning and a product-level warning configured. The 'Sale Warnings' setting is enabled. How are these warnings displayed?

- Only the partner warning is shown; product warnings require a separate setting
- Both warnings are concatenated and displayed together on the sales order form **(True)**
- Each warning triggers a separate blocking popup that must be dismissed individually

### 27. You confirm a sales order, then cancel it, then click 'Set to Quotation' to return it to draft. What happens to the procurement group that was created on confirmation?

- The procurement group is deleted and a new one is created on re-confirmation
- The procurement group remains linked to the order and is reused **(True)**
- Odoo blocks returning a canceled order to draft if a procurement group exists

### 28. What are the possible program types available in the Loyalty module in Odoo 19?

- Coupons, Promotions, Loyalty Cards, and Gift Cards only
- Coupons, Gift Card, Loyalty Cards, Promotions, eWallet, Discount Code, Buy X Get Y, and Next Order Coupons **(True)**
- Coupons, Promotions, Gift Cards, Subscriptions, and Referral Rewards

### 29. When creating an invoice from a sales order, what is the effect of enabling 'Consolidated Billing'?

- All selected sales orders are merged into a single invoice regardless of the customer
- Invoice lines from multiple sales orders of the same customer are grouped into one invoice **(True)**
- Each sales order line becomes a separate invoice for better tracking

---

## Sales -- Additional II (10 questions)

### 30. How can you offer a free product when a customer buys a specific quantity of another product?

- Create a discount code with a reward of free product.
- Use a promotion program with a "Buy X Get Y" rule. **(True)**
- Configure a pricelist with a special price for the combination.
- Set up a cross-selling rule on the product form.

> Source: `addons/sale_loyalty/models/sale_order.py` — `_get_reward_values_product()` asserts `reward.reward_type == 'product'` and builds reward lines with `reward_product_qty * claimable_count` at 100% discount. The `sale_loyalty` module implements "Buy X Get Y" via `loyalty.reward` with `reward_type='product'`.

---

### 31. What happens to a sales order when you change the customer's currency after confirming the order?

- The currency updates automatically, and all prices are converted using the current exchange rate.
- The currency cannot be changed after confirmation; the field becomes read-only. **(True)**
- A warning appears, but you can still change it if you have special rights.
- The order is canceled and a new one must be created.

> Source: `addons/sale/models/sale_order.py` — `write()` raises `UserError` if `'pricelist_id' in vals` for any confirmed order (`state == 'sale'`). `currency_id` is computed from `pricelist_id`, so locking the pricelist effectively makes currency read-only on confirmed orders.

---

### 32. How do you enable sales representatives to see only their own quotations and orders?

- Set up record rules based on the salesperson field. **(True)**
- Use the "My Sales" filter in the list view.
- Assign each salesperson to a separate sales team.
- Enable the "Personalized Sales" setting in the user preferences.

> Source: `addons/sale/security/ir_rules.xml` — `sale_order_personal_rule` applies domain `['|',('user_id','=',user.id),('user_id','=',False)]` to `group_sale_salesman`, restricting standard salespeople to their own orders only.

---

### 33. What is the purpose of the "Delivery Method" field on a sales order?

- To specify the carrier used for shipping and compute shipping costs. **(True)**
- To indicate the preferred delivery date.
- To define the route for the inventory move.
- To set the delivery address.

> Source: `addons/delivery/models/sale_order.py` — `carrier_id = fields.Many2one('delivery.carrier', string="Delivery Method", help="Fill this field if you plan to invoice the shipping based on picking.")`. The `set_delivery_line()` method uses it to create a delivery cost line on the SO.

---

### 34. How can you create a quotation that automatically expires after a certain date?

- Set a validity date on the quotation template or on the quotation itself. **(True)**
- Configure a scheduled action to cancel expired quotations.
- Use a server action to set the state to expired.
- The validity date is only available for eCommerce quotations.

> Source: `addons/sale/models/sale_order.py` — `validity_date` field is computed by `_compute_validity_date()` using `order.company_id.quotation_validity_days`; also editable directly on the quotation form. The online portal disables sign/pay once the date passes.

---

### 35. What is the difference between "Invoice from Delivery" and "Invoice from Order" invoicing policies?

- "Invoice from Delivery" creates invoices based on delivered quantities, while "Invoice from Order" creates invoices based on ordered quantities. **(True)**
- "Invoice from Delivery" is used for services, "Invoice from Order" for goods.
- They are synonyms; no difference.
- "Invoice from Delivery" requires the Inventory app, while "Invoice from Order" does not.

> Source: `addons/sale/models/product_template.py` — `invoice_policy = fields.Selection([('order', "Ordered quantities"), ('delivery', "Delivered quantities")])`. `'order'` invoices on confirmation; `'delivery'` invoices after stock moves are validated.

---

### 36. How can you prevent a sales order from being edited after it is confirmed?

- Enable the "Lock Confirmed Sales" setting in Sales configuration. **(True)**
- Set the user's rights to read-only on confirmed orders.
- Archive the sales order after confirmation.
- There is no way; confirmed orders can always be edited.

> Source: `addons/sale/models/sale_order.py` — `locked` field prevents modifications; `_should_be_locked()` checks `sale.group_auto_done_setting` (UI label: "Lock Confirmed Sales"). Once locked, `action_cancel()` also raises an error until the order is explicitly unlocked.

---

### 37. How do you handle a customer return of products that were sold and delivered?

- Create a return delivery order and then a credit note. **(True)**
- Directly create a credit note without returning products.
- Create a new sales order with negative quantities.
- Use the "Reverse" button on the invoice.

> Source: `addons/sale/tests/test_sale_refund.py` — `test_refund_create` validates the full flow: post invoice → create `account.move.reversal` (credit note of type `out_refund`) → verify `qty_to_invoice` and `qty_invoiced` update correctly across the return delivery and refund.

---

### 38. What is the role of the "Sales Team" in the sales process?

- To group salespeople for reporting and commission purposes. **(True)**
- To define the warehouse from which products are delivered.
- To set the default pricelist for customers.
- To manage the sales order approval workflow.

> Source: `addons/sale/models/crm_team.py` — `invoiced` and `invoiced_target` fields track monthly revenue vs. target per team. `sale_order_count` counts linked orders. Teams are used for dashboard reporting and performance tracking.

---

### 39. How can you add a discount to a sales order line without using a pricelist?

- Enter a discount percentage directly in the "Discount" field on the line. **(True)**
- Create a negative line with a product "Discount".
- Use a promotion code that applies a discount.
- Discounts can only be applied via pricelists.

> Source: `addons/sale/models/sale_order_line.py` — `discount = fields.Float(string="Discount (%)", compute='_compute_discount', store=True, readonly=False)`. The column is only visible when the user belongs to `sale.group_discount_per_so_line` ("Discount on lines"), enabled in Sales settings.

---

## Purchase -- Additional (10 questions)

### 18. The Purchase Order Approval setting is enabled with a minimum amount of $5,000. A user confirms a PO for $3,000. What happens?

- The PO goes to 'To Approve' status and requires manager approval
- The PO is confirmed directly without requiring approval because it is below the threshold **(True)**
- Odoo blocks the confirmation and asks the user to request approval

### 19. You cancel a purchase order that has a partially completed receipt (some items already received). What happens to the completed receipt?

- The completed receipt is reversed and items are returned to the vendor location
- The completed receipt remains untouched, but a message is posted on it noting the PO was cancelled **(True)**
- Odoo blocks the cancellation until a return is created for the received items

### 20. In the vendor pricelist (_select_seller), when multiple vendor lines match the same product and quantity, what is the primary sorting criterion Odoo uses to pick the best one?

- The vendor line with the lowest sequence number
- The vendor line with the lowest discounted price in company currency **(True)**
- The vendor line most recently created (highest ID)

### 21. What happens to vendor pricelist entries (supplierinfo) when a blanket order is closed (set to 'Done')?

- They remain active so future RFQs can still reference the agreed pricing
- They are unlinked/deleted from the products **(True)**
- They are archived but can be restored by reopening the blanket order

### 22. In a call for tenders, you click the 'Choose' button on a specific vendor's RFQ line. What does Odoo do to competing alternatives?

- Competing alternative POs are automatically canceled
- Quantities on competing alternative lines for the same product are set to zero **(True)**
- Competing alternatives are moved to a 'Rejected' state

### 23. The 3-way matching feature shows an 'Exception' status on a vendor bill line. Which of the following could cause this?

- The invoice unit price differs from the purchase order price **(True)**
- The vendor bill was created before the PO was confirmed
- The product category does not match the PO line

### 24. What are the three possible values of the 3-way matching status field (`can_be_paid`) on a vendor bill line?

- 'Approved', 'Rejected', 'Pending'
- 'Yes', 'No', 'Exception' **(True)**
- 'Matched', 'Unmatched', 'Partial'

### 25. In a dropshipping setup, what is the source and destination of the stock move created by the dropship route?

- Source: company warehouse, Destination: customer location
- Source: vendor/supplier location, Destination: customer location **(True)**
- Source: vendor/supplier location, Destination: company warehouse

### 26. A product has 3 vendor pricelist lines for the same vendor: Line A (min qty 1, price $10, seq 1), Line B (min qty 5, price $8, seq 2), Line C (min qty 10, price $7, seq 3). You purchase 7 units. Which line is selected?

- Line A, because it has the lowest sequence
- Line B, because it is the largest quantity threshold not exceeding 7 **(True)**
- Line C, because $7 is the cheapest price

### 27. What is the technical model name used for both blanket orders and call for tenders in Odoo 19?

- `purchase.blanket.order` and `purchase.tender`
- `purchase.requisition` for both **(True)**
- `purchase.agreement` for both

---

## Accounting -- Additional (17 questions)

### 21. What are the possible values for the 'amount_type' field on a bank reconciliation model line?

- Fixed, Percentage, and Python Code
- Fixed, Percentage of balance, Percentage of statement line, and From label (regex) **(True)**
- Amount, Rate, Formula, and Manual

### 22. What is the difference between a tax with amount_type 'percent' and one with 'division' (Percentage Tax Included)?

- 'percent' adds tax on top of the base (e.g., 100 * 1.10 = 110), while 'division' works by dividing the total (e.g., 180 / 0.90 = 200) **(True)**
- 'percent' is for sales taxes only, while 'division' is for purchase taxes only
- There is no functional difference; they are just UI labels for the same calculation

### 23. In which countries is Storno accounting mandatory in Odoo 19?

- Germany, Austria, Switzerland, and Italy
- Bosnia, China, Czech Republic, Croatia, Poland, Romania, Serbia, Russia, Slovenia, Slovakia, and Ukraine **(True)**
- All EU member states

### 24. A Belgian company sets up an early payment discount on a payment term. What is the default tax reduction computation for Belgium?

- 'On early payment' (included)
- 'Always (upon invoice)' (mixed) **(True)**
- 'Never' (excluded)

### 25. How many lock date types exist in Odoo 19 Accounting, and which one cannot have exceptions?

- 3 types; the Tax Lock Date cannot have exceptions
- 5 types (Global, Tax, Sales, Purchase, Hard); the Hard Lock Date cannot have exceptions **(True)**
- 4 types; none of them allow exceptions once set

### 26. When you partially pay an invoice ($80 out of $100), does Odoo create additional journal entries for the reconciliation?

- Yes, a separate reconciliation journal entry is created for the $80 match
- No, reconciliation is tracked via link records (partial reconcile) between existing journal entry lines **(True)**
- Yes, both a payment entry and a write-off entry are created automatically

### 27. What is the relationship between `account.partial.reconcile` and `account.full.reconcile`?

- They are the same model with different states
- A full reconcile is a container that groups multiple partial reconciles when all lines balance to zero **(True)**
- A partial reconcile is created first and then upgraded to a full reconcile when paid in full

### 28. Which account type value in Odoo 19 represents the 'Current Year Earnings' account?

- `equity`
- `equity_unaffected` **(True)**
- `equity_current_year`

### 29. What does the 'Invoicing Switch Threshold' date in Accounting settings do?

- It switches the invoicing policy from 'ordered' to 'delivered' after that date
- It automatically cancels all journal entries from before that specific date **(True)**
- It blocks the creation of new invoices until the threshold date has passed

### 30. A tax has `price_include_override` set to 'tax_excluded', but the company default is set to 'tax_included'. Which setting wins?

- The individual tax setting always overrides the company default **(True)**
- The company default overrides the individual tax setting
- Odoo shows a conflict warning and asks the user to choose

### 31. How can you prevent the creation or the modification of journal entries up to a specific accounting date?

- By closing a period
- By setting a lock date to lock a fiscal period **(True)**
- By posting all journal entries
- It is not possible to block the creation or modification of journal entries

### 32. Which of the following depreciation methods does NOT exist in Odoo?

- Straight line
- Declining
- Sum of the years **(True)**
- Declining, then straight line

### 33. What does it mean when a line item in the 'Match Existing Entries' section of the bank reconciliation screen is highlighted in blue?

- It is showing a registered payment **(True)**
- A payment is registered in another currency than the default currency
- It represents an invoice

### 34. How do you compute the total due by a customer?

- The sum of all unpaid invoices of this customer
- The balance related to this customer in receivable accounts **(True)**
- The sum of customer invoices minus the sum of vendor bills
- The sum of all unpaid invoices and draft invoices of this customer

### 35. How can the reference of a journal entry be changed?

- By going to the journal entry and changing it, independently of its status **(True)**
- By going to the journal entry and changing it, but only if it's in draft status
- By first enabling 'Editable settings' in Accounting > Configurations, and then going to the journal entry and changing it
- Journal entry references cannot be changed in Odoo

### 36. What happens when you post a vendor bill with an accounting date in the previous fiscal period that has already been locked?

- Odoo doesn't let you post the vendor bill, preventing you from creating a journal entry in a locked fiscal period
- Odoo automatically changes the accounting date to be in the next open fiscal period and posts the vendor bill **(True)**
- The locked fiscal period mechanism doesn't apply here
- Odoo automatically changes the accounting date to match the bill date

### 37. What changes when enabling the accounting firm mode?

- The document's sequence becomes editable on all documents
- A new field 'Total (tax inc.)' to speed up and control the encoding by automating line creation with the right account and tax
- A default Customer Invoice / Vendor Bill date will be suggested
- All of the above **(True)**

---

## MRP -- Additional (10 questions)

### 22. What are the only two BoM types available in Odoo 19?

- Manufacture and Subcontracting
- Manufacture this product (normal) and Kit (phantom) **(True)**
- Standard and Configurable

### 23. How many states does a manufacturing order go through in Odoo 19?

- 4 states: Draft, Confirmed, Done, Cancelled
- 6 states: Draft, Confirmed, In Progress, To Close, Done, Cancelled **(True)**
- 5 states: Draft, Confirmed, In Progress, Done, Cancelled

### 24. How is OEE (Overall Equipment Effectiveness) calculated for a work center in Odoo?

- (Total units produced / Maximum possible units) * 100
- (Productive time / (Productive time + Blocked time)) * 100 **(True)**
- (Actual duration / Expected duration) * 100

### 25. A product with a Kit (phantom) BoM is added to a sales order and confirmed. What happens?

- A manufacturing order is created to assemble the kit before delivery
- The delivery order explodes the kit into its component stock moves; no MO is created **(True)**
- Odoo asks the user whether to manufacture or pick components directly

### 26. What does the 'Ready to Produce' setting on a BoM control?

- Whether the MO can be started without confirming the BoM
- Whether the MO is considered 'Ready' when all components are available, or when only components for the first operation are available **(True)**
- Whether the MO auto-starts when components arrive at the production location

### 27. What are the possible values of the `reservation_state` field on a manufacturing order?

- 'unreserved', 'partially_reserved', 'fully_reserved'
- 'confirmed' (Waiting), 'assigned' (Ready), 'waiting' (Waiting Another Operation) **(True)**
- 'draft', 'waiting', 'ready', 'in_progress'

### 28. During an active manufacturing order (not yet done), you scrap a component. From which location is the scrap sourced?

- The finished goods location (location_dest_id)
- The raw materials / source location (location_src_id) **(True)**
- The virtual production location

### 29. You want to split a manufacturing order of 100 units into batches. The BoM has a batch size of 25 with 'Enable Batch Size' checked. How many MOs will the split wizard propose?

- 2 MOs of 50 units each
- 4 MOs of 25 units each **(True)**
- 1 MO of 100 units (batch size only affects MPS)

### 30. What happens if you try to unbuild a product when you have zero units on hand?

- Odoo blocks the unbuild completely and shows an error
- Odoo shows a warning about insufficient quantity, but you can still confirm the unbuild **(True)**
- Odoo automatically creates an inventory adjustment to add the missing units first

### 31. In Odoo 19, which record links related manufacturing orders (parent MO and its backorders/splits) together?

- `stock.picking.batch`
- `mrp.production.group` **(True)**
- `mrp.routing.workcenter`

---

## Payroll (10 questions)

### 1. Which module provides the base work entry model (`hr.work.entry`) in Odoo 19?

- `hr_payroll` (enterprise)
- `hr_work_entry` (community addons) **(True)**
- `hr_attendance` (community addons)

### 2. What are the possible states of a work entry in Odoo 19?

- Draft, Confirmed, Validated, Cancelled
- Draft, Conflict, Validated (In payslip), Cancelled **(True)**
- New, Approved, Processed, Archived

### 3. What does the `amount_rate` field on a work entry type control?

- The hourly rate for the employee
- The pay rate multiplier (e.g., 2.0 for double pay, 1.5 for overtime) **(True)**
- The percentage of the base salary allocated to that entry type

### 4. What are the possible states of a payslip (`hr.payslip`) in Odoo 19?

- Draft, Confirmed, Paid, Cancelled
- Draft, Validated, Paid, Canceled **(True)**
- New, Approved, Posted, Closed

### 5. Which of the following is NOT a valid computation type (`amount_select`) for a salary rule?

- Python Code
- Percentage
- Formula **(True)**

### 6. What are the possible values for the `work_entry_source` field on an employee contract, which determines how work entries are generated?

- Manual, Automatic, and Hybrid
- Calendar (Working schedule), Attendance, and Planning **(True)**
- Timesheet, Schedule, and Absence

### 7. How many pay schedule options are available on a salary structure type in Odoo 19?

- 4 (Weekly, Bi-weekly, Monthly, Annually)
- 9 (Daily, Weekly, Bi-weekly, Semi-monthly, Monthly, Bi-monthly, Quarterly, Semi-annually, Annually) **(True)**
- 3 (Monthly, Quarterly, Annually)

### 8. You change an employee's working schedule mid-month. What happens to their existing draft work entries for that month?

- They remain unchanged until the next payroll cycle
- A regeneration wizard allows you to archive old entries and regenerate new ones based on the updated schedule **(True)**
- Odoo automatically deletes and recreates all work entries without user intervention

### 9. When a payslip is validated, what does the `hr_payroll_account` module create?

- A payment order sent to the bank
- An accounting journal entry (account.move) with debit/credit lines based on salary rule accounts **(True)**
- A PDF report and an email notification to the employee

### 10. What does the `batch_payroll_move_lines` company setting control in Odoo 19 Payroll?

- Whether payslips in a batch are validated together or one by one
- Whether payroll journal entries are grouped into one entry per batch, or one entry per payslip **(True)**
- Whether employees in the same department are batched into a single payslip

---

## Inventory -- Additional (7 questions)

### 1. Where do you define the cost price of a product variant?

- At the attribute value level
- At the product variant level **(True)**
- At the product template level

### 2. When purchasing a product, when is the quantity on hand of that product increased?

- When the purchase order is validated
- When the receipt is validated **(True)**
- When the vendor bill is posted


### 3. When performing an inventory adjustment, what is created when applying the counted quantities for several product lines at the same time?

- One stock move for the whole inventory adjustment
- One stock move per adjustment line with an updated quantity **(True)**
- One stock move per product included in the inventory adjustment


### 4. Where is the costing method defined?

- On the product form
- On the product category form **(True)**
- On the company (all products have the same costing method)

### 5. When you manually update the quantity on hand of a product via the "Update Quantity" button on the product form view, does it generate a stock move?

- Yes **(True)**
- No


### 6. You have 20 units of a table in stock. 10 of those units belong to you, and the other 10 belong to their owner, Azure Interior. What is your inventory valuation for the tables, if they cost you $500/unit?

- $5,000.00 (only your 10 units) **(True)**
- $10,000.00 (total including consignment stock)
- $500.00

### 7. With which costing methods can 'Landed Costs' be used?

- AVCO only
- FIFO only
- Both FIFO & AVCO **(True)**

---

## Inventory -- Expiration & Barcodes (2 questions)

### 1. You can set an expiration date on new products received to your inventory at which stage of the receipt process?

- When the products are received
- Once the lots are in stock
- A&B (Both when received and once lots are in stock) **(True)**

### 2. Can you enter barcodes manually in the Barcode app?

- Yes **(True)**
- No

---

## Warehouse & Shipping (2 questions)

### 1. I want to configure a specific route in my warehouse for FedEx, but it needs to be different than the route we use for DHL. I can do this by:

- Going to Inventory > Configuration > Shipping Methods and choosing a route for the Routes field
- Going to Inventory > Configuration > Shipping Methods and creating two shipping methods for DHL and FedEx
- Create a custom route for the shipping method and setting it in the Routes field in Inventory > Configuration > Shipping Methods **(True)**

### 2. How do you look up which products have been sitting in stock longest?

- Go to Reporting > Moves History and group by 'Date' **(True)**
- Navigate to Inventory > Stock and group by 'Duration'
- Go to Reporting > Stock Aging

---

## Manufacturing -- ECO, Repair & MPS (8 questions)

### 1. Can you define a work order operation without a work center?

- Yes, but no work order will be generated
- No, defining a work center is mandatory **(True)**

### 2. What is the purpose of an Engineering Change Order (ECO)?

- To create customized products based on sales orders
- To make changes to a BoM or introduce a new product **(True)**
- To modify an existing manufacturing order

### 3. When are stock moves registered for a repair order?

- Upon confirmation of the repair order
- When starting the repair order
- After finishing the repair order **(True)**

### 4. What do the additional row options Actual Demand Y-1 and Actual Demand Y-2 refer to in the Master Production Schedule (MPS)?

- The quantity of products sold at this time last year and two years ago, respectively **(True)**
- The quantity of products delivered to customer locations at the same time last year and two years ago
- The demand forecast input in the MPS this time last year and two years ago

### 5. Where can you access a consolidated overview of component lead times and projected product availability?

- On the Master Production Schedule
- On the BoM 'Overview' **(True)**
- On the manufacturing order

### 6. What must happen in order to mark a subcontracted order as complete?

- The subcontractor must validate component consumption from the subcontracting portal
- The user must validate the receipt of the product from the subcontractor **(True)**
- The finished product must be shipped

### 7. What happens when you click the 'Mark as Done' button on a work order card in the Shop Floor module?

- The work order card fades away, and the card for the next work order appears in the Shop Floor module **(True)**
- The work order card fades away, and the manufacturing order is closed
- The work order card remains visible, but is marked as 'Done'

### 8. What happens when no employees are listed in the 'Allowed Employees' field on a work center form?

- No employee is allowed to operate the work center
- It is not possible to leave the 'Allowed Employees' field blank
- Any employee is allowed to operate the work center **(True)**

---

## HR -- Additional (6 questions)

### 1. As an HR officer, what is the most effective method to engage a senior manager in the recruitment process of a promising candidate?

- Add the senior manager as a follower of the applicant
- On the job position, set the senior manager as Recruiter
- Set the senior manager as an Interviewer on the applicant
- All of the above **(True)**

### 2. How can you create an eLearning course that can only be accessed by paying online?

- There is no option to create a paid course
- By checking the option 'all courses are paid' in the settings
- By enabling paid courses in the settings and setting the enroll policy to be 'on payment' **(True)**
- By enabling paid courses in the settings and setting the enroll policy to be 'on confirmation of quotation'

### 3. Where is the default work entry type of an employee defined in Odoo?

- Employees > Configuration > Settings > Work Organization: Default Work Entry Type
- Payroll > Configuration > Salary: Structure Types > Structure Type form > Default Work Entry Type **(True)**
- Attendances > Configuration > Extra Hours: Default Work Entry Type
- Settings > Users & Companies: Companies > Company form > General Information: Default Work Entry Type

### 4. If you wanted to set a color for 'Sick Time Off' (as displayed in the dashboard view of the Time Off module), where would you go to do this?

- From Configuration > Time Off Types **(True)**
- From the Calendar view of your leaves
- This is not something you can configure

### 5. Which condition must be met for an expense to be created from an email?

- The person submitting the expense needs to have an Odoo user account associated with their email address
- The person submitting the expense needs to have an Odoo user account OR an employee associated with their email address **(True)**
- None of the above

### 6. When looking at a job listing, what does the smart button 'Trackers' allow you to do?

- It allows you to track which medium applicants are using to apply (LinkedIn, Twitter, Facebook, etc.) **(True)**
- Access people to whom we sent recruitment letters
- Define employees involved in the recruitment process for this position

---

## Spreadsheet -- Additional (3 questions)

### 1. When you share a dashboard using the share button, what will you actually share?

- A URL leading to the Document workspace where the dashboard is stored
- A URL leading to a frozen version in read only mode **(True)**
- You cannot share a dashboard

### 2. How can you make sure new records are added to your pivot?

- By generating extra lines at the right place to display them
- By using the 'ODOO.PIVOT.TABLE' function **(True)**
- Both of them

### 3. How can you remove extra space characters in a range of cells?

- By using the 'Delete' function/option
- By using the 'Trim' function/option **(True)**
- Both of them

---

## POS -- Additional (3 questions)

### 1. The choice of a payment acquirer depends on various factors such as:

- Your shop's country and your business needs
- Your shop's country, your business needs, your business turnover and your business sector
- Your shop's country, your business needs, your business turnover, your business sector and your PoS set-up **(True)**

### 2. What are the means of payment that cannot be used when ordering at a kiosk?

- Pay at cashier
- Pay by cash using an integrated cash drawer **(True)**
- Pay online with your phone

### 3. How can you generate an invoice for your customers in POS?

- From the payment screen, if the customer is registered
- They can generate one themselves by scanning a QR code on their receipt
- Both answers are correct **(True)**

---

## Technical (3 questions)

### 1. How do global and group-specific record rules interact?

- Global rules cannot be bypassed, and group-specific rules can only expand access within the limits defined by the global rules **(True)**
- Global rules can be expanded by group-specific rules to widen a user's access
- Global rules are ignored if a group-specific rule applies to a user

### 2. What does it mean when text is highlighted in blue in the report editor?

- These elements are highlighted for customer visibility
- These are placeholders for elements that may vary from one instance of the report to another **(True)**
- These elements are conditionally visible

### 3. What happens when you modify the footer of an invoice report?

- The footer is modified for all invoice reports
- The footer is modified for all reports within the same model
- The footer is modified for all reports **(True)**

---

## Accounting & Invoicing -- Additional III (42 questions)

### 38. What do fiscal localizations do?

- They allow you to map taxes and accounts based on the customer or vendor.
- They ensure that your database meets all of your country's accounting requirements and norms. **(True)**
- They create journal entries to incorporate the price of customs duties and fees into the cost of products.
- They automatically reconcile your bank transactions with the appropriate invoice or bill.

### 39. What does it mean for a journal entry to be balanced?

- It has the same number of debit lines and credit lines.
- It has the same amount of debits and credits. **(True)**
- It appears in both a customer invoice journal and a vendor bills journal.
- Journal entries cannot be balanced.

### 40. The general ledger is

- A list of all the customer invoices and vendor bills that haven't been paid.
- A list of the income and expense accounts.
- A list of all the journal items grouped by their journal entries.
- A list of all of the accounts and their debits and credits. **(True)**

### 41. How many Chart of Accounts can you have per company?

- One per company, and one per database.
- As many as there are on the database.
- One per company, but multiple per database. **(True)**

### 42. What happens if no currency is set on an account?

- A currency must be set on an account.
- The account automatically defaults to the company's currency if no currency is set.
- If no currency is set, the account can be used with any currency. **(True)**

### 43. What is the default account type shown first in the account field when creating an invoice?

- Expense and Fixed Assets accounts
- Income accounts **(True)**
- Income and Fixed Assets accounts


### 44. What is recommended for accounts I do not need?

- Delete the unneeded accounts.
- Deprecate the unneeded accounts.
- Archive the unneeded accounts. **(True)**

### 45. I do not need the "Current Year Earnings" account. What can I do with it?

- The account is Odoo-specific and should NOT be modified in any way. **(True)**
- I can delete or deprecate it, it is only for specific use-cases.
- I can modify and tailor it to my specific business needs.


### 46. What account should replace the bank account when importing a positive (debit) amount?

- The suspense account
- The outstanding payments account
- The outstanding receipts account **(True)**
- The cash account

> Positive (debit) amount = money received into the bank. The outstanding receipts account holds inflows until they are reconciled with a bank transaction. This is the correct counterpart for positive bank amounts during opening balance import.

### 47. Which of the following processes is the best way to import open invoices and bills?

- Add each invoice or bill as one line in the import template with the remaining amount to be paid as the total and import to the corresponding model. **(True)**
- Add each line of each invoice or bill as its own line in the import template so that the invoice or bill has all of the details in Odoo and import to the corresponding model.
- Import invoices and bills directly from the general ledger view by opening the action menu and clicking "Import Invoice/Bill".
- Combine them into one sheet, then import them through the Import Wizard in the Accounting Settings.

### 48. What's the purpose of replacing the receivable and payable accounts on the general ledger with the clearing account?

- It's impossible to import to receivable or payable accounts.
- By importing to the clearing account, you don't have to import your open invoices or bills.
- It gives you an entry to reconcile the opening bank transaction against.
- It avoids duplicating the balance in the receivable and payable accounts when importing both the general ledger and the open invoices and bills. **(True)**

### 49. If you create an invoice for Azure Interior with 1 product "Large Desk", and a 15% tax. What are the journal items created?

- 2 Lines: Product Sales, Account Receivable
- 2 Lines: Product Sales, Account Payable
- 3 Lines: Product Sales, Tax Received, Account Receivable **(True)**
- 2 Lines: Product Sales, Tax Received

### 50. In the journal items, what defines the amounts your customer owes you?

- A debit in Account Payable
- A debit in Account Receivable **(True)**
- A credit in Account Payable
- A credit in Account Receivable

### 51. Where can you define the default income account that is used on an invoice?

- On the product form, or the product category, or the sales journal. **(True)**
- On the product form, but not on the product category or sales journal.
- On the journal only.

### 52. What options could you add to an invoice to improve its structure?

- Colors and notes
- Colors and sections
- Sections and notes **(True)**

### 53. Is it possible to select all "Draft" invoices and post them in one action?

- Yes **(True)**
- No

### 54. In the Sales app, open S00007 from Gemini Furniture. You can see that the Quantity, Delivered, and Invoiced values of some sales order lines are blue and others are black. Why is that?

- A blue line means that this sales order line is invoiceable. **(True)**
- A black line means that this product is invoiceable.
- A blue line means that the product has been delivered.
- A blue line means that the products have already been invoiced.

### 55. In Odoo, how can you create one invoice for multiple sales orders belonging to the same customer and invoicing address?

- From the sales order form view, click Create Invoice, then click Include additional invoices and select the appropriate sales orders to invoice.
- From the sales order list view, select multiple sales orders, click Actions > Create invoice(s), check Consolidated Billing, and click Create Draft. **(True)**
- From the invoice list view, click New, then set the Type field to Batch, and select the appropriate sales orders to invoice.
- Multiple sales orders cannot have one invoice in Odoo.

### 56. Which of the following workflows will cause an Invalid Operation error when creating an invoice from a sales order?

- Creating a regular invoice when not all order lines are invoiceable.
- Creating a down payment (percentage) invoice with a percentage over 100%.
- Creating a down payment (fixed amount) invoice with an amount greater than the amount remaining to be invoiced.
- Creating a regular invoice when no order lines are invoiceable. **(True)**

### 57. How can you create a dedicated credit note sequence?

- By posting the credit note in draft and re-writing the sequence.
- By enabling the setting on the 'Customer Invoices' journal. **(True)**
- By creating a specific 'Credit Notes' journal.

### 58. If you create a $100 credit note from a $100 invoice, what will the journal entries look like?

- $100 from the Income Account in the CREDIT column and $100 from the Receivable Account in the DEBIT column.
- $100 from the Income Account in the DEBIT column and $100 from the Receivable Account in the CREDIT column. **(True)**
- The journal entries remain unchanged when creating a credit note.
- The entries are the same as the initial customer invoice journal entries.

### 59. You invoiced a set of wine glasses and cutlery to a customer, but the glasses arrived broken. You want to refund only the glasses. How do you do it?

- Create an invoice with a negative amount and wire transfer the amount to the customer.
- Bill yourself the glasses and wire transfer the bill amount to the customer.
- Create a credit note from the invoice and remove the cutlery from the credit note's products, then confirm it. **(True)**

### 60. You refunded only the set of wine glasses, the cutlery remains invoiced. You have not received any payment from the customer yet for that invoice. The credit note was created through the invoice, confirmed, and sent. What is the status of the invoice related to that credit note?

- In payment.
- Fully paid.
- Partially paid. **(True)**

### 61. When posting a credit note created from an invoice, what is the note automatically reconciled with?

- The payment of the credit note.
- With itself.
- With the invoice. **(True)**

### 62. In the journal items tab on a vendor bill, what defines the amount you owe to the vendor?

- A credit in the Account Payable **(True)**
- A debit in the Account Payable
- A credit in the Account Receivable
- A debit in the Account Receivable

### 63. If a bill has two different products with the same tax. What are the journal items created?

- 2 Payables, 1 Expense, 2 Taxes
- 2 Payables, 2 Expenses, 2 Taxes
- 1 Payable, 2 Expenses, 1 Tax **(True)**

### 64. When you add products to a bill, the account is automatically filled in as "60000 Expenses". Why is that account selected by default?

- This account comes from the vendor's payable account field in the accounting tab of the vendor's contact record.
- This Expenses account comes from the customer's payment account.
- Open the vendor's form and check the accounting tab to verify this answer.
- The Expenses account is the Vendor Bill journal's default account. To verify this answer, open the journal's form view from the Configuration menu. **(True)**

### 65. How can a vendor bill be created?

- Manually, by adding a document to the calendar meetings.
- Manually, by uploading a document, and by sending an email to an email alias. **(True)**
- Automatically by sending an email to the administrator of the database.

### 66. What happens when you upload a PDF with multiple bills in Odoo?

- Odoo automatically separates the PDF into the individual bills based on the OCR.
- Odoo suggests where each bill should be separated but asks you to confirm the separation. **(True)**
- Clicking on the scissors button allows you to choose where to split the PDF.
- Bills must be uploaded in separate PDF files.

### 67. What does the OCR do?

- Recognize which texts on the bill belong in which fields in Odoo **(True)**
- Predict information based on past bills from this vendor
- Automatically add any new fields present on the bill that aren't in Odoo
- Automatically separate a PDF with multiple bills into individual bills

### 68. What aspects are affected by the Payment Terms?

- The due date.
- The due date, the payment conditions, and any payment incentives. **(True)**
- All the rules and guidelines the customer must agree to.
- The due date and the taxes are applied to the invoice.

### 69. Is it possible to customize your T&Cs related to a specific invoice/order/quotation?

- Yes, you can update the default T&Cs in the document when you create it. **(True)**
- Yes, but only if the modifications are related to minor changes.
- No, you have to modify the default T&Cs.
- No, T&Cs cannot be updated.

### 70. What are the different formats available for T&C on the invoice?

- Text on the invoice and link to the webpage on the invoice. **(True)**
- Text on the invoice and QR code on the invoice.
- Link to the webpage on the invoice and QR code on the invoice.

### 71. What are outstanding accounts used for?

- They are temporary holding accounts used to mark unpaid invoices and bills for the aged receivables and aged payables reports.
- They are temporary holding accounts used to record the registered payment of an invoice or bill until the payment can be reconciled with the bank transaction. **(True)**
- They are temporary holding accounts used to balance the registered partial payment of an invoice or bill until the full payment is made.
- They are temporary holding accounts used for batch payments.

### 72. When is an invoice or bill marked as "Paid" in Odoo?

- When any payment is made on the invoice or bill, regardless of the amount.
- When the full payment or the invoice/bill itself is reconciled with the bank transaction. **(True)**
- When the full payment is registered and linked to that invoice or bill.
- When the full payment is registered.

> Note: After registering payment, the invoice shows "In Payment" (not "Paid"). The status only becomes "Paid" once reconciliation with the bank statement occurs.

### 73. What is the purpose of the "Group Payments" option?

- To have all invoices or bills under one single payment.
- To have only one payment per partner instead of per bill. **(True)**
- To group up bills by payment type.
- To group all reconciled payments into one group and all unreconciled payments into another group.

### 74. How does using the "Pay" button on an invoice or bill differ from manually creating a payment for the same amount?

- The "Pay" button automatically reconciles the payment with the invoice or bill. **(True)**
- The "Pay" button automatically reconciles the payment with the bank transaction.
- The "Pay" button automatically reconciles the payment with the invoice or bill and also automatically reconciles it with the bank transaction.
- The "Pay" button automatically pays the full invoice or bill amount, whereas manually creating a payment is the only way to register a partial payment.

### 75. How can I bypass the need for transaction reconciliation in the case of cash payments?

- On the Cash journal, set the payment method's "Outstanding Payments" account to the journal's main 'Cash' account. Then use this payment method when registering the payment. **(True)**
- On the Cash journal, set the payment method's "Outstanding Payments" account to an 'outstanding' account. Then use this payment method when registering the payment.
- Create a manual payment, set the journal to "Cash" and then link that payment to the invoice or bill.
- On the Cash journal, leave the "Outstanding Payments" account of the blank.

### 76. When the Country field in the Configuration tab of a payment provider is empty, this means that

- This payment provider is not available for customers in any country.
- This payment provider is available for customers in all countries. **(True)**
- This payment provider is available only for customers in the same country as the company.
- The payment provider cannot be activated until the country field is populated.

### 77. How can the message that is displayed in the customer portal when an invoice is paid online be modified?

- From the payment provider record, enter Studio and edit the message text.
- From the customer portal, enter Studio and edit the message text.
- From the payment provider record, open the Messages tab and edit the message text. **(True)**
- This message is not modifiable.

### 78. What is the payment status of an invoice after being paid online?

- Received
- Paid
- Paid online
- In payment **(True)**


### 79. What actions are available when defining a follow-up?

- Email, SMS, letter, WhatsApp. **(True)**
- Email, SMS, voicemail, letter.
- Email, SMS only.

---

## Sales -- Batch 3 (5 questions)

### 1. In a quotation template, what does the "Expiration Date" field determine?

- The date when the template itself becomes inactive.
- The default validity period (in days) applied to quotations created from this template. **(True)**
- The deadline for customers to accept optional products.
- The date after which the template can no longer be edited.

---

### 2. How can you allow customers to order products that are temporarily out of stock in the eCommerce shop?

- Set the product's "Out of Stock" field to "Allow orders" on the product form (Sales tab). **(True)**
- Enable the "Backorder" setting in Website > Configuration.
- Configure a reordering rule to trigger purchase orders automatically.
- This is not possible; out-of-stock products are always hidden.

---

### 3. What happens when you create a sales order for a product with a "Discount" entered on the order line and the "Margin" setting is enabled?

- The margin calculation ignores the discount and uses the original price.
- The margin is recalculated based on the discounted unit price. **(True)**
- The margin field becomes hidden until the order is confirmed.
- Odoo shows a warning that margins cannot be computed with discounts.

---

### 4. Which of the following is a valid option for the "Shipping" field on a product's Sales tab?

- Deliver all products at once.
- Deliver the first product immediately, others later.
- Ship each product as soon as it is available. **(True)**
- Wait for full payment before shipping.

---

### 5. When you add a "Section" line to a quotation, what does the section contain?

- Only a title — sections are purely visual dividers with no pricing or product data. **(True)**
- Products that are grouped together and can be optionally selected by the customer.
- A list of products with their own prices and quantities.
- Hidden notes visible only to internal users.

---

## Purchase -- Batch 2 (4 questions)

### 1. In a purchase order, what does the "Incoterm" field represent?

- The shipping method used for delivery.
- The international commercial terms defining responsibilities for delivery, risk, and costs. **(True)**
- The currency exchange rate applicable to the order.
- The vendor's internal reference for the order.

---

### 2. What is the purpose of the "Minimum Order Quantity" field on a vendor price list line?

- To require the vendor to accept orders only above that quantity.
- To define the smallest quantity that triggers this price from this vendor. **(True)**
- To trigger a warning if the ordered quantity is less than the minimum.
- To automatically add the minimum quantity to the purchase order.

---

### 3. When you receive a purchase order partially and later create a vendor bill, how is the quantity to invoice determined if the product's control policy is "On received quantities"?

- The bill automatically includes only the received quantity. **(True)**
- The bill includes the full ordered quantity; you must manually adjust it.
- Odoo prevents creating a bill until all products are received.
- The bill is created for the ordered quantity, and a credit note is generated for the unreceived amount.

---

### 4. In a "Call for Tenders" purchase agreement, what happens when you select a winning vendor and confirm?

- A single purchase order is created for all selected lines from that vendor. **(True)**
- Multiple purchase orders are created, one per product.
- The tender is marked as done and no orders are generated.
- The vendor receives an email asking for final confirmation.

---

## Inventory -- Batch 2 (4 questions)

### 1. In the "Storage Categories" feature, what does the "Capacity" field on a storage category define?

- The maximum number of different products that can be stored in that category.
- The maximum total quantity that can be stored in a location assigned to that category. **(True)**
- The maximum number of pallets allowed in the location.
- The maximum weight capacity of the location.

---

### 2. When performing an inventory adjustment and you enter a counted quantity of zero for a product that previously had stock, what stock move is generated?

- A move from the storage location to the inventory loss location for the entire on-hand quantity. **(True)**
- A move from the inventory loss location to the storage location for zero quantity.
- No move is created; the system simply updates the quantity field.
- A move from the storage location to the inventory valuation account.

---

### 3. What does the "Replenish" button on a product form do?

- It opens the reordering rule configuration for that product.
- It opens a wizard to create a one-off procurement order (purchase or manufacturing) to restock the product. **(True)**
- It triggers the scheduler to run for that product only.
- It displays a forecast report of the product's availability.

---

### 4. In the "Packages" feature, what is the primary purpose of a "Package Type"?

- To define the physical characteristics (dimensions, max weight) of packages for shipping carrier integration. **(True)**
- To assign a barcode to the package automatically.
- To group packages by destination location.
- To set the weight of the package contents automatically.

---

## Manufacturing -- Batch 2 (4 questions)

### 1. In a Bill of Materials, what does the "Operations" tab specify?

- The sequence of work centers and operations required to manufacture the product. **(True)**
- The list of components and their quantities needed for production.
- The default manufacturing order template.
- The quality control points to be checked during production.

---

### 2. What happens when you click "Plan" on a manufacturing order that has operations defined?

- Work orders are created for each operation and scheduled according to the work center routing. **(True)**
- The manufacturing order is confirmed and ready to start without creating work orders.
- Odoo generates a production schedule for the next planning period.
- The raw materials are reserved for the first operation only.

---

### 3. What is the purpose of the "Resupply Subcontractor on Order" route?

- To send raw material components from the company's warehouse to the subcontractor when a purchase order is confirmed. **(True)**
- To have the subcontractor purchase raw materials directly from a third-party vendor.
- To deliver finished goods directly from the subcontractor to the customer.
- To create an internal manufacturing order at the subcontractor's location.

---

### 4. What does the "Time Efficiency" field on a work center affect?

- The percentage of productive time versus total recorded time for OEE reporting.
- The duration of operations — values above 100% reduce planned duration (e.g., 150% efficiency means the operation takes 2/3 of the nominal time). **(True)**
- The number of employees that can work simultaneously at this work center.
- The hourly cost rate of the work center.

---

## Accounting -- Batch 2 (4 questions)

### 1. In Odoo 19, how do you configure different taxes for customers in a specific country?

- Create a Fiscal Position with tax mappings and enable auto-detection by country; Odoo applies it automatically based on the customer's location. **(True)**
- On the product form's Accounting tab, add per-country tax overrides.
- In Sales settings, configure a tax table per country group.
- This is not possible; taxes are always applied globally regardless of customer location.

---

### 2. What does the "Journal Items" button on a validated invoice display?

- The list of account move lines (journal items) generated by this invoice. **(True)**
- A popup showing the full journal entry in edit mode.
- A reconciliation wizard to match the invoice with payments.
- The invoice's PDF report.

---

### 3. When you register a payment from the "Pay" button on an invoice, where is the payment posted initially?

- To the outstanding receipts/payments account defined on the payment method's journal. **(True)**
- Directly to the receivable account of the customer, bypassing the outstanding account.
- To a suspense account until manual reconciliation with the bank statement.
- To the bank account specified on the payment, immediately.

---

### 4. How can you prevent users from posting journal entries with an accounting date that falls in a locked period?

- Set a lock date in Accounting > Configuration > Settings for the relevant period. **(True)**
- Change the user's access rights to read-only for past periods.
- Delete the fiscal period from the fiscal year configuration.
- Odoo automatically blocks all posting in any date prior to today.

---

## Project -- Batch 2 (4 questions)

### 1. What does the "Timesheets" smart button on a task display?

- The total hours logged on that task and the list of individual timesheet entries. **(True)**
- The list of employees currently assigned to the task.
- The project's overall timesheet summary across all tasks.
- The billing status and invoiced amount for the task.

---

### 2. How can you make a task repeat automatically on a recurring schedule?

- Set a recurrence rule on the task form using the "Recurrence" option. **(True)**
- Use a scheduled action to duplicate the task at the desired interval.
- Recurring tasks are only possible at the project level, not individual tasks.
- Create a task template and manually copy it each period.

---

### 3. When you create a subtask, what relationship is established with the parent task?

- The subtask is linked via a `parent_id` field and can belong to a different project than the parent. **(True)**
- The subtask must be in the same project as the parent task.
- The subtask automatically inherits the parent's stage and deadline.
- The subtask cannot have its own subtasks (nesting is limited to one level).

---

### 4. In project reporting, what does the "Days to Deadline" measure represent?

- The number of calendar days remaining from today until the task's deadline date. **(True)**
- The number of days since the task was created.
- The total planned duration of the project in working days.
- The average completion time for all tasks in the project.

---

## Payroll -- Batch 2 (4 questions)

### 1. In the Payroll app, what is the purpose of a "Salary Rule"?

- To define the formula, conditions, and accounts for computing an employee's pay component (e.g., basic salary, overtime, deductions). **(True)**
- To set the employee's base hourly rate directly.
- To determine the frequency at which payslips are generated.
- To record the employee's bank account details for payment.

---

### 2. How are work entries generated for an employee whose contract uses the "Calendar (Working schedule)" source?

- Automatically by the system based on the employee's working schedule at the start of each payroll period. **(True)**
- Manually by the HR manager for each pay period.
- Through the Attendance app when the employee clocks in and out.
- They are not generated automatically; work entries must be created from the Planning app.

---

### 3. What is the role of "Input" type salary rules in a salary structure?

- To create an input field on payslips where users can manually enter variable amounts (e.g., bonuses). **(True)**
- To define fixed amounts that are the same for every employee in every period.
- To link timesheet data to the payslip computation automatically.
- To compute the tax amounts based on gross salary.

---

### 4. What happens when you validate a payslip?

- The payslip is set to "Done" and, if the payroll accounting module is installed, an accounting journal entry is created. **(True)**
- It automatically sends the payslip PDF to the employee by email.
- It marks all related work entries as validated and locks attendance records.
- It automatically transfers the net salary to the employee's bank account.

---

## Timesheets -- Batch 2 (5 questions)

### 1. What does the "Grid" view in the Timesheets app allow you to do?

- Enter timesheet entries in a spreadsheet-like interface grouped by employee, project, or task across a time period. **(True)**
- View a Gantt chart of all timesheet entries over time.
- Approve timesheet lines in bulk across multiple employees.
- Generate invoices directly from timesheet entries.

---

### 2. How can you prevent employees from entering timesheets for future dates?

- Uncheck "Allow future timesheets" in Timesheets > Configuration > Settings. **(True)**
- Use a scheduled action to delete any future-dated entries nightly.
- This is not configurable; employees can always log any date.
- Set the employee's contract end date to today's date.

---

### 3. What does the "Encoding Unit" field on a project determine?

- Whether timesheets for tasks in this project are entered in hours or days. **(True)**
- The billing unit used when generating invoices from timesheets.
- The default unit of measure for all product lines on the related sales order.
- The unit displayed in project progress reports.

---

### 4. When a timesheet line is linked to a sales order item with a "Prepaid / Fixed Price" invoicing policy, how is the timesheet treated for invoicing?

- The timesheet does not increase the quantity to invoice; it only tracks progress against the prepaid amount. **(True)**
- Each timesheet line generates an additional invoice line for the hours worked.
- It reduces the prepaid balance and triggers a new invoice for the remainder.
- It requires manual approval before the hours can be counted toward the invoice.

---

### 5. What is the effect of enabling a timesheet "Validation" policy on a project?

- Timesheet entries require manager approval before they can be locked or used for invoicing. **(True)**
- Timesheet entries are automatically validated and locked as soon as they are saved.
- Employees cannot edit timesheet entries at all after they submit them.
- Validated timesheets are automatically forwarded to the project manager by email.

---
