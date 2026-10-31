using System;

namespace Church.Core
{
    public interface IMultiTenantEntity
    {
        Guid TenantId { get; set; }
    }
}
