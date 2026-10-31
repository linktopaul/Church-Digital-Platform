using System;

namespace Church.Core
{
    public class Tenant
    {
        public Guid Id { get; set; }
        public string Name { get; set; }
        public string Slug { get; set; }
        public string ContactEmail { get; set; }
        public string LogoUrl { get; set; }
        public DateTime CreatedAt { get; set; }
        public string Status { get; set; }
    }
}
