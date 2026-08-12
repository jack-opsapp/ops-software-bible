UPDATE companies SET max_seats = 3
 WHERE subscription_plan = 'starter' AND max_seats <> 3;

UPDATE companies SET max_seats = 5
 WHERE subscription_plan = 'team' AND max_seats <> 5;

UPDATE companies SET max_seats = 10
 WHERE subscription_plan = 'business' AND max_seats <> 10;
